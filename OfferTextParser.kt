package com.driverintelligence.domain.recognition

import com.driverintelligence.domain.model.OfferData
import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Extrai os dados de uma oferta a partir do texto reconhecido na tela.
 *
 * Não depende de layout fixo: procura padrões (valor monetário, pares "tempo (distância)",
 * rótulos como "Viagem" e "de distância") e usa a geometria das linhas, quando disponível,
 * para desambiguar (o valor da corrida é o maior texto próximo dos pares de distância).
 */
class OfferTextParser {

    private data class MoneyHit(
        val value: Double,
        val lineIndex: Int,
        val startIndex: Int,
        val isPlus: Boolean,
        val rateUnit: String?,
        val isExtra: Boolean,
    )

    fun parse(frame: OcrFrame): ParseResult {
        val notes = mutableListOf<String>()

        // 1. Remove linhas do próprio overlay e normaliza confusões de dígitos.
        var corrections = 0
        val rawLines = frame.lines.filter { line ->
            val n = line.text.uppercase()
            !(n.contains("DRIVER INTELLIGENCE") || n.startsWith("DI ·"))
        }
        val ordered = if (rawLines.isNotEmpty() && rawLines.all { it.box != null }) {
            rawLines.sortedWith(compareBy<OcrLine>({ it.box!!.top }, { it.box!!.left }))
        } else rawLines
        val lines = ordered.map { line ->
            val (fixed, n) = NumberNormalizer.fixDigitConfusions(line.text.replace(' ', ' ').trim())
            corrections += n
            line.copy(text = fixed)
        }
        val hasGeometry = lines.isNotEmpty() && lines.all { it.box != null }

        val text = lines.joinToString("\n") { it.text }
        val lineStarts = IntArray(lines.size)
        run {
            var pos = 0
            lines.forEachIndexed { i, l ->
                lineStarts[i] = pos
                pos += l.text.length + 1
            }
        }
        fun lineOf(index: Int): Int {
            var lo = 0
            var hi = lineStarts.size - 1
            var ans = 0
            while (lo <= hi) {
                val mid = (lo + hi) ushr 1
                if (lineStarts[mid] <= index) {
                    ans = mid
                    lo = mid + 1
                } else hi = mid - 1
            }
            return ans
        }

        // 2. Valores monetários.
        val moneyHits = MONEY.findAll(text).mapNotNull { m ->
            val value = NumberNormalizer.parse(m.groupValues[2], thousandsHint = true) ?: return@mapNotNull null
            val lineIdx = lineOf(m.range.first)
            val lineNorm = normalize(lines.getOrNull(lineIdx)?.text.orEmpty())
            val rate = m.groups[3]?.value?.let { normalize(it).replace("/", "").trim() }
            MoneyHit(
                value = value,
                lineIndex = lineIdx,
                startIndex = m.range.first,
                isPlus = m.groups[1] != null,
                rateUnit = rate,
                isExtra = EXTRA_KEYWORDS.any { lineNorm.contains(it) },
            )
        }.toList()

        // 3. Pares tempo + distância.
        var pairs = findPairs(text, ::lineOf, PAIR, reversed = false)
        if (pairs.isNotEmpty() && pairs.all { it.minutes == null }) {
            val alt = findPairs(text, ::lineOf, PAIR_REVERSED, reversed = true)
            if (alt.isNotEmpty() && alt.any { it.minutes != null }) pairs = alt
        }

        var pickup = pairs.firstOrNull { it.label == PairLabel.PICKUP }
        var trip = pairs.firstOrNull { it.label == PairLabel.TRIP }
        val unlabeled = pairs.filter { it.label == PairLabel.UNLABELED }
        var orderInferred = false
        when {
            pickup == null && trip == null -> {
                if (unlabeled.size >= 2) {
                    pickup = unlabeled[0]
                    trip = unlabeled[1]
                    orderInferred = true
                    notes += "Ordem busca/viagem deduzida pela posição."
                } else if (unlabeled.size == 1) {
                    notes += "Apenas um par tempo/distância visível."
                }
            }
            pickup == null -> {
                val t = trip!!
                pickup = unlabeled.lastOrNull { it.startIndex < t.startIndex }
                if (pickup != null) orderInferred = true
            }
            trip == null -> {
                val p = pickup!!
                trip = unlabeled.firstOrNull { it.startIndex > p.startIndex }
                if (trip != null) orderInferred = true
            }
        }
        val assigned = listOfNotNull(pickup, trip).size
        val extraPairs = (pairs.size - assigned).coerceAtLeast(0)

        // 4. Valor da corrida.
        val fareCandidates = moneyHits.filter { !it.isPlus && it.rateUnit == null && !it.isExtra }
        val anchorLine = (pickup ?: trip)?.lineIndex
        var fareAmbiguous = false
        val fareHit: MoneyHit? = when {
            fareCandidates.isEmpty() -> null
            fareCandidates.size == 1 -> fareCandidates[0]
            hasGeometry -> {
                val heights = fareCandidates.map { lines[it.lineIndex].box!!.height.coerceAtLeast(1) }
                val maxH = heights.max().toDouble()
                val anchorTop = anchorLine?.let { lines[it].box!!.top }
                val span = if (frame.height > 0) frame.height * 0.35 else 600.0
                val scored = fareCandidates.mapIndexed { i, hit ->
                    val hScore = heights[i] / maxH
                    val proximity = if (anchorTop != null) {
                        1.0 - min(1.0, abs(lines[hit.lineIndex].box!!.centerY - anchorTop) / span)
                    } else 0.0
                    hit to (0.6 * hScore + 0.4 * proximity)
                }.sortedByDescending { it.second }
                if (scored.size > 1 && scored[0].second - scored[1].second < 0.08 && scored[0].first.value != scored[1].first.value) {
                    fareAmbiguous = true
                }
                scored[0].first
            }
            else -> {
                val firstPairIndex = listOfNotNull(pickup, trip).minOfOrNull { it.startIndex }
                val before = if (firstPairIndex != null) fareCandidates.filter { it.startIndex < firstPairIndex } else emptyList()
                if (fareCandidates.map { it.value }.distinct().size > 1 && before.size != 1) fareAmbiguous = true
                before.lastOrNull() ?: fareCandidates.first()
            }
        }
        if (fareAmbiguous) notes += "Mais de um valor monetário candidato."

        val surge = moneyHits.filter { it.isPlus || it.isExtra }.maxOfOrNull { it.value }
        val displayedRate = moneyHits.firstOrNull { it.rateUnit == "km" }?.value

        // 5. Campos secundários.
        val category = CATEGORY.find(text)?.value?.let { canonicalCategory(it) }
        val rating = RATING.findAll(text).firstNotNullOfOrNull { m ->
            val raw = m.groups[1]?.value ?: m.groups[2]?.value
            raw?.let { NumberNormalizer.parse(it) }?.takeIf { it in 1.0..5.0 }
        }
        val origin = pickup?.let { addressAfter(lines, it.lineIndex) }
        val destination = trip?.let { addressAfter(lines, it.lineIndex) }

        // 6. Detecção da tela de oferta.
        val normText = normalize(text)
        val hasAcceptButton = ACCEPT_KEYWORDS.any { normText.contains(it) }
        val isOfferScreen = (fareHit != null && (pickup != null || trip != null)) ||
            (hasAcceptButton && (fareHit != null || pairs.isNotEmpty()))

        // 7. Confiança da leitura.
        var confidence = 0.0
        if (fareHit != null) confidence += 0.35
        pickup?.let { confidence += if (it.minutes != null) 0.25 else 0.18 }
        trip?.let { confidence += if (it.minutes != null) 0.25 else 0.18 }
        if (pickup != null && trip != null) confidence += if (orderInferred) 0.07 else 0.15
        confidence -= min(0.15, 0.05 * corrections)
        if (fareAmbiguous) confidence -= 0.20
        confidence -= min(0.10, 0.05 * extraPairs)
        confidence = confidence.coerceIn(0.0, 1.0)
        if (corrections > 0) notes += "$corrections correção(ões) de dígitos aplicada(s)."

        val offer = OfferData(
            fare = fareHit?.value,
            pickupDistanceKm = pickup?.km,
            tripDistanceKm = trip?.km,
            pickupTimeMin = pickup?.minutes,
            tripTimeMin = trip?.minutes,
            category = category,
            origin = origin,
            destination = destination,
            surgeAmount = surge,
            displayedRatePerKm = displayedRate,
            passengerRating = rating,
        )
        return ParseResult(
            offer = offer,
            confidence = confidence,
            isOfferScreen = isOfferScreen,
            orderInferred = orderInferred,
            fareAmbiguous = fareAmbiguous,
            ocrCorrections = corrections,
            notes = notes,
        )
    }

    private fun findPairs(text: String, lineOf: (Int) -> Int, regex: Regex, reversed: Boolean): List<TimeDistancePair> {
        val result = mutableListOf<TimeDistancePair>()
        for (m in regex.findAll(text)) {
            val hoursRaw: String?
            val minutesRaw: String?
            val distRaw: String
            val unitRaw: String
            if (!reversed) {
                hoursRaw = m.groups[1]?.value
                minutesRaw = m.groups[2]?.value
                distRaw = m.groups[3]?.value ?: continue
                unitRaw = m.groups[4]?.value ?: continue
            } else {
                distRaw = m.groups[1]?.value ?: continue
                unitRaw = m.groups[2]?.value ?: continue
                hoursRaw = m.groups[3]?.value
                minutesRaw = m.groups[4]?.value
            }
            val rawKm = NumberNormalizer.parse(distRaw) ?: continue
            val km = when (unitRaw.lowercase()) {
                "m" -> rawKm / 1000.0
                "mi" -> rawKm * 1.609344
                else -> rawKm
            }
            val hours = hoursRaw?.let { NumberNormalizer.parse(it) }
            val mins = minutesRaw?.let { NumberNormalizer.parse(it) }
            val minutes = if (hours == null && mins == null) null else (hours ?: 0.0) * 60.0 + (mins ?: 0.0)

            val lineIdx = lineOf(m.range.first)
            val lineStart = text.lastIndexOf('\n', m.range.first - 1).let { if (it < 0) 0 else it + 1 }
            val prevLineStart = if (lineStart <= 1) 0 else text.lastIndexOf('\n', lineStart - 2).let { if (it < 0) 0 else it + 1 }
            val lineEnd = text.indexOf('\n', m.range.last + 1).let { if (it < 0) text.length else it }
            val sameLineBefore = normalize(text.substring(lineStart, m.range.first))
            val prevLine = normalize(text.substring(prevLineStart, lineStart))
            val after = normalize(text.substring(m.range.last + 1, lineEnd))
            val nextLine = run {
                if (lineEnd >= text.length) "" else {
                    val e = text.indexOf('\n', lineEnd + 1).let { if (it < 0) text.length else it }
                    normalize(text.substring(lineEnd + 1, e))
                }
            }
            val label = when {
                TRIP_KEYWORDS.any { sameLineBefore.contains(it) || after.contains(it) } -> PairLabel.TRIP
                PICKUP_KEYWORDS.any { sameLineBefore.contains(it) || after.contains(it) } -> PairLabel.PICKUP
                // Rótulo em linha própria ("Viagem" acima / "de distância" abaixo)
                TRIP_KEYWORDS.any { prevLine.trim() == it || prevLine.trim().startsWith("$it ") || prevLine.trim().startsWith("$it:") } -> PairLabel.TRIP
                PICKUP_SUFFIX_LINES.any { nextLine.trim() == it } -> PairLabel.PICKUP
                else -> PairLabel.UNLABELED
            }
            result += TimeDistancePair(minutes, km, label, m.range.first, lineIdx)
        }
        return result
    }

    private fun addressAfter(lines: List<OcrLine>, pairLine: Int): String? {
        for (i in pairLine + 1..min(lines.size - 1, pairLine + 2)) {
            val t = lines[i].text.trim()
            val n = normalize(t)
            if (n.isBlank()) continue
            if (PICKUP_SUFFIX_LINES.any { n == it }) continue
            if (MONEY.containsMatchIn(t) || PAIR_DISTANCE_ONLY.containsMatchIn(t)) return null
            if (ACCEPT_KEYWORDS.any { n.contains(it) } || REJECT_KEYWORDS.any { n == it }) return null
            if (TRIP_KEYWORDS.any { n == it || n.startsWith("$it ") || n.startsWith("$it:") }) return null
            val letters = t.count { it.isLetter() }
            if (letters >= 4) return t.take(80)
        }
        return null
    }

    private fun canonicalCategory(raw: String): String {
        val n = raw.lowercase().replace(" ", "")
        return CATEGORY_CANONICAL[n] ?: raw.trim()
    }

    companion object {
        /** Grupo 1: "+"; grupo 2: número; grupo 3: sufixo de taxa ("/km", "/h"). */
        val MONEY = Regex(
            """(\+\s?)?(?:R\s?[${'$'}S5]|\${'$'})\s?(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{1,2})?)(?!\d)(\s?/\s?(?:km|hr|hora|h|min))?""",
            RegexOption.IGNORE_CASE,
        )

        /** Grupos: 1 horas, 2 minutos, 3 distância, 4 unidade. */
        val PAIR = Regex(
            """(?:(\d{1,2})\s*h(?:oras?|r)?\s*)?(?:(\d{1,3}(?:[.,]\d)?)\s*(?:minutos|minuto|mins|min)\.?\s*)?[(\[{]?\s*(\d{1,3}(?:[.,]\d{1,3})?)\s*(km|mi|m)(?![a-zA-Z])\s*[)\]}]?""",
            RegexOption.IGNORE_CASE,
        )

        /** Distância antes do tempo ("1,2 km · 4 min"). Grupos: 1 distância, 2 unidade, 3 horas, 4 minutos. */
        val PAIR_REVERSED = Regex(
            """(\d{1,3}(?:[.,]\d{1,3})?)\s*(km|mi)(?![a-zA-Z])\s*[·•,|\-–]?\s*[(\[{]?\s*(?:(\d{1,2})\s*h\s*)?(\d{1,3})\s*(?:minutos|minuto|mins|min)""",
            RegexOption.IGNORE_CASE,
        )

        private val PAIR_DISTANCE_ONLY = Regex("""\d+(?:[.,]\d+)?\s*(?:km|mi)(?![a-zA-Z])""", RegexOption.IGNORE_CASE)

        val CATEGORY = Regex(
            """\b(Uber\s?XL|Uber\s?X|Comfort|Black\s?Bag|Black|Uber\s?Flash|Flash\s?Moto|Flash|Uber\s?Moto|Moto|Juntos|Promo|Prioridade|Priority|Pet|Envios|Exclusivo)\b""",
            RegexOption.IGNORE_CASE,
        )

        private val CATEGORY_CANONICAL = mapOf(
            "uberx" to "UberX", "uberxl" to "UberXL", "comfort" to "Comfort", "black" to "Black",
            "blackbag" to "Black Bag", "uberflash" to "Flash", "flash" to "Flash", "flashmoto" to "Flash Moto",
            "ubermoto" to "Moto", "moto" to "Moto", "juntos" to "Juntos", "promo" to "Promo",
            "prioridade" to "Prioridade", "priority" to "Prioridade", "pet" to "Pet", "envios" to "Envios",
            "exclusivo" to "Exclusivo",
        )

        private val RATING = Regex("""[★*][ \t]*(\d[.,]\d{1,2})|(\d[.,]\d{1,2})[ \t]*[★*]""")

        private val TRIP_KEYWORDS = listOf("viagem", "trip", "percurso", "corrida de")
        private val PICKUP_KEYWORDS = listOf("de distancia", "distancia", "away", "embarque", "ate voce", "ate o passageiro", "pickup")
        private val PICKUP_SUFFIX_LINES = listOf("de distancia", "distancia", "away")
        private val ACCEPT_KEYWORDS = listOf("aceitar", "accept", "toque para aceitar")
        private val REJECT_KEYWORDS = listOf("recusar", "decline", "x")
        private val EXTRA_KEYWORDS = listOf(
            "inclui", "incluido", "dinamic", "promo", "gorjeta", "bonus", "taxa", "surge", "boost", "includes", "adicional",
        )

        fun normalize(s: String): String =
            Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")

        @Suppress("unused")
        private fun clamp01(v: Double) = max(0.0, min(1.0, v))
    }
}
