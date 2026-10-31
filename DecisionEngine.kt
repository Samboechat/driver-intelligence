package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.Decision
import com.driverintelligence.domain.model.ESSENTIAL_FIELDS
import com.driverintelligence.domain.model.FinancialResult
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.Metric
import com.driverintelligence.domain.model.MetricScore
import com.driverintelligence.domain.model.OfferField
import com.driverintelligence.domain.model.ScoringConfig
import com.driverintelligence.domain.util.Br
import kotlin.math.roundToInt

/**
 * Classificação de rentabilidade baseada em vários indicadores ponderados.
 *
 * Cada indicador recebe uma nota 0..1 em relação à meta do motorista:
 *  - "maior é melhor": 60% da meta → 0; meta → 0,7; 125% da meta → 1,0 (linear entre os pontos)
 *  - "menor é melhor": mesma curva aplicada à razão limite ÷ valor
 * A nota final é a média ponderada dos indicadores disponíveis (pesos renormalizados).
 *
 * Regras rígidas aplicadas depois da nota:
 *  - Lucro operacional estimado ≤ 0 → VERMELHO.
 *  - Lucro abaixo do mínimo por corrida, ou distância total acima do limite → no máximo AMARELO.
 *
 * O motor apenas recomenda. Nunca aceita ou recusa corridas.
 */
class DecisionEngine {

    fun decide(
        result: FinancialResult,
        goals: Goals,
        config: ScoringConfig = ScoringConfig(),
        recognitionConfidence: Double? = null,
    ): Decision {
        val missingEssentials = result.missingInputs.filter { it in ESSENTIAL_FIELDS }
        if (missingEssentials.isNotEmpty() || result.grossRevenue == null) {
            val list = missingEssentials.joinToString(", ") { it.label }
            return gray("Dados insuficientes: falta $list.", listOf("Confira a oferta na tela ou use a inserção manual."))
        }
        if (recognitionConfidence != null && recognitionConfidence < config.minRecognitionConfidence) {
            val pct = (recognitionConfidence * 100).roundToInt()
            return gray(
                "Leitura incerta ($pct% de confiança). Confira os valores na tela.",
                listOf("A recomendação só é emitida com confiança mínima de ${(config.minRecognitionConfidence * 100).roundToInt()}%."),
            )
        }

        val scores = buildList {
            higher(Metric.REVENUE_PER_KM, result.revenuePerKm, goals.minRevenuePerKm, config)?.let(::add)
            higher(Metric.PROFIT_PER_KM, result.profitPerKm, goals.minProfitPerKm, config)?.let(::add)
            higher(Metric.REVENUE_PER_HOUR, result.revenuePerHour, goals.minRevenuePerHour, config)?.let(::add)
            higher(Metric.PROFIT_PER_HOUR, result.profitPerHour, goals.minProfitPerHour, config)?.let(::add)
            lower(Metric.PICKUP_TIME, result.unproductiveTimeMin, goals.maxPickupMinutes, config)?.let(::add)
            val unproductiveShare = result.productiveDistanceShare?.let { 1.0 - it }
            lower(Metric.UNPRODUCTIVE_DISTANCE, unproductiveShare, goals.maxUnproductiveShare, config)?.let(::add)
            val costShare = if (result.totalCost != null && result.grossRevenue > 0) result.totalCost / result.grossRevenue else null
            lower(Metric.COST_SHARE, costShare, goals.maxCostShare, config)?.let(::add)
        }

        if (scores.size < 2) {
            return gray("Indicadores insuficientes para recomendar.", listOf("Informe tempos e custos do veículo para uma análise completa."))
        }

        val weightSum = scores.sumOf { it.weight }
        val weighted = if (weightSum > 0.0) {
            scores.sumOf { it.score * it.weight } / weightSum
        } else {
            scores.sumOf { it.score } / scores.size
        }

        var classification = when {
            weighted >= config.greenThreshold -> Classification.GREEN
            weighted >= config.yellowThreshold -> Classification.YELLOW
            else -> Classification.RED
        }

        val hardWeaknesses = mutableListOf<String>()
        val profit = result.operatingProfit
        if (profit != null && profit <= 0.0) {
            classification = Classification.RED
            hardWeaknesses += "prejuízo estimado de ${Br.money(-profit)}"
        } else {
            val minProfit = goals.minProfitPerTrip
            if (minProfit != null && profit != null && profit < minProfit) {
                if (classification == Classification.GREEN) classification = Classification.YELLOW
                hardWeaknesses += "lucro estimado abaixo da sua meta"
            }
            val maxTotal = goals.maxTotalDistanceKm
            val total = result.totalDistanceKm
            if (maxTotal != null && total != null && total > maxTotal) {
                if (classification == Classification.GREEN) classification = Classification.YELLOW
                hardWeaknesses += "distância total acima do seu limite"
            }
        }

        val weaknesses = scores
            .filter { !it.meetsTarget }
            .sortedByDescending { it.weight * (1.0 - it.score) }
            .map { it.metric.weakness }
        val strengths = scores
            .filter { it.meetsTarget }
            .sortedByDescending { it.weight * it.score }
            .map { it.metric.strength }

        val allWeaknesses = (weaknesses + hardWeaknesses).distinct()
        // Na manchete, regras rígidas (ex.: lucro abaixo da meta) aparecem por último, como no texto natural.
        val headlineWeaknesses = (weaknesses.take(if (hardWeaknesses.isEmpty()) 2 else 1) + hardWeaknesses.take(1)).distinct()

        val headline = when (classification) {
            Classification.GREEN -> {
                val parts = listOfNotNull(
                    result.revenuePerKm?.let { Br.perKm(it) },
                    (result.revenuePerHour ?: result.profitPerHour)?.let { Br.perHour(it) },
                )
                "Boa rentabilidade: ${joinPt(parts)}."
            }
            Classification.YELLOW ->
                if (headlineWeaknesses.isEmpty()) "Rentabilidade moderada." else "Rentabilidade moderada: ${joinPt(headlineWeaknesses)}."
            Classification.RED ->
                if (headlineWeaknesses.isEmpty()) "Não recomendada: abaixo das suas metas." else "Não recomendada: ${joinPt(headlineWeaknesses)}."
            Classification.GRAY -> "Dados insuficientes."
        }

        val reasons = buildList {
            allWeaknesses.forEach { add(it.replaceFirstChar { c -> c.uppercase() }) }
            strengths.forEach { add(it.replaceFirstChar { c -> c.uppercase() }) }
            if (result.isCostEstimatePartial) {
                add("Estimativa parcial: custos não configurados (${result.missingCosts.joinToString(", ") { it.label.lowercase() }}).")
            }
            if (OfferField.PICKUP_TIME in result.missingInputs || OfferField.TRIP_TIME in result.missingInputs) {
                add("Tempo não identificado: indicadores por hora indisponíveis.")
            }
        }

        val isPartial = result.isCostEstimatePartial ||
            OfferField.PICKUP_TIME in result.missingInputs ||
            OfferField.TRIP_TIME in result.missingInputs

        return Decision(
            classification = classification,
            score = weighted,
            headline = headline,
            reasons = reasons,
            metricScores = scores,
            isPartial = isPartial,
        )
    }

    private fun gray(headline: String, reasons: List<String>) = Decision(
        classification = Classification.GRAY,
        score = null,
        headline = headline,
        reasons = reasons,
        metricScores = emptyList(),
        isPartial = true,
    )

    private fun higher(metric: Metric, value: Double?, target: Double, config: ScoringConfig): MetricScore? {
        if (value == null || !value.isFinite()) return null
        val weight = config.weights.weightOf(metric).coerceAtLeast(0.0)
        return MetricScore(metric, value, target, scoreHigherIsBetter(value, target), weight)
    }

    private fun lower(metric: Metric, value: Double?, limit: Double, config: ScoringConfig): MetricScore? {
        if (value == null || !value.isFinite()) return null
        val weight = config.weights.weightOf(metric).coerceAtLeast(0.0)
        return MetricScore(metric, value, limit, scoreLowerIsBetter(value, limit), weight)
    }

    companion object {
        fun scoreHigherIsBetter(value: Double, target: Double): Double {
            if (target <= 0.0) return 1.0
            val r = value / target
            return when {
                r >= 1.25 -> 1.0
                r >= 1.0 -> 0.7 + (r - 1.0) / 0.25 * 0.3
                r >= 0.6 -> (r - 0.6) / 0.4 * 0.7
                else -> 0.0
            }
        }

        fun scoreLowerIsBetter(value: Double, limit: Double): Double {
            if (value <= 0.0) return 1.0
            if (limit <= 0.0) return 0.0
            return scoreHigherIsBetter(limit / value, 1.0)
        }

        fun joinPt(parts: List<String>): String = when (parts.size) {
            0 -> ""
            1 -> parts[0]
            else -> parts.dropLast(1).joinToString(", ") + " e " + parts.last()
        }
    }
}
