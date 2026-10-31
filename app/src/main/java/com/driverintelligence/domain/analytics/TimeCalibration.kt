package com.driverintelligence.domain.analytics

import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.min

/** Tempo prometido na oferta × tempo real medido numa corrida aceita. */
data class TimingSample(
    val at: Long,
    val offeredPickupMin: Double?,
    val actualPickupMin: Double?,
    val offeredTripMin: Double?,
    val actualTripMin: Double?,
)

enum class FactorSource(val label: String) {
    DEFAULT("estimativa padrão"),
    LEARNED("aprendido com suas corridas"),
    LEARNED_HOUR("aprendido para este horário"),
}

/** Multiplicadores do tempo exibido na oferta (1,35 = a busca real leva 35% a mais). */
data class TimeFactors(
    val pickup: Double,
    val trip: Double,
    val pickupSource: FactorSource,
    val tripSource: FactorSource,
    val pickupSamples: Int,
    val tripSamples: Int,
) {
    val isLearned: Boolean get() = pickupSource != FactorSource.DEFAULT || tripSource != FactorSource.DEFAULT
}

/**
 * Aprende quanto os tempos da oferta costumam atrasar na prática.
 *
 * Usa a mediana (resistente a corridas atípicas) das últimas [window] corridas medidas.
 * Se há amostras suficientes no mesmo horário (±1 h), usa só elas — trânsito de pico pesa diferente.
 * Sem amostras suficientes, usa os fatores padrão definidos pelo motorista.
 */
class TimeCalibration(
    samples: List<TimingSample>,
    private val defaultPickup: Double = 1.35,
    private val defaultTrip: Double = 1.15,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val minSamples: Int = 5,
    private val window: Int = 40,
) {
    private data class Ratio(val hour: Int, val value: Double)

    private val recent = samples.sortedByDescending { it.at }.take(window)
    private val pickupRatios = ratios { it.offeredPickupMin to it.actualPickupMin }
    private val tripRatios = ratios { it.offeredTripMin to it.actualTripMin }

    private fun ratios(pick: (TimingSample) -> Pair<Double?, Double?>): List<Ratio> = recent.mapNotNull { s ->
        val (offered, actual) = pick(s)
        if (offered == null || actual == null || offered < 1.0 || actual <= 0.0) return@mapNotNull null
        val r = actual / offered
        if (r !in 0.3..5.0) return@mapNotNull null
        Ratio(Instant.ofEpochMilli(s.at).atZone(zone).hour, r)
    }

    fun factorsAt(hour: Int): TimeFactors {
        val (p, ps, pn) = pick(pickupRatios, hour, defaultPickup)
        val (t, ts, tn) = pick(tripRatios, hour, defaultTrip)
        return TimeFactors(p, t, ps, ts, pn, tn)
    }

    /** Fatores gerais (sem filtro de horário), para exibir nas estatísticas. */
    fun overall(): TimeFactors {
        val (p, ps, pn) = pick(pickupRatios, null, defaultPickup)
        val (t, ts, tn) = pick(tripRatios, null, defaultTrip)
        return TimeFactors(p, t, ps, ts, pn, tn)
    }

    private fun pick(list: List<Ratio>, hour: Int?, default: Double): Triple<Double, FactorSource, Int> {
        if (hour != null) {
            val near = list.filter { hourDistance(it.hour, hour) <= 1 }
            if (near.size >= minSamples) return Triple(clamp(median(near.map { it.value })), FactorSource.LEARNED_HOUR, near.size)
        }
        if (list.size >= minSamples) return Triple(clamp(median(list.map { it.value })), FactorSource.LEARNED, list.size)
        return Triple(default, FactorSource.DEFAULT, list.size)
    }

    companion object {
        fun median(values: List<Double>): Double {
            val s = values.sorted()
            val n = s.size
            return if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2.0
        }

        fun clamp(v: Double) = v.coerceIn(0.6, 3.0)

        private fun hourDistance(a: Int, b: Int): Int {
            val d = abs(a - b)
            return min(d, 24 - d)
        }
    }
}

/**
 * Compara uma oferta com as que o motorista já recebeu.
 * Só responde com amostra mínima, para não inventar conclusão.
 */
class OfferBenchmark(revenuePerKm: List<Double>, private val minSamples: Int = 10) {
    private val sorted = revenuePerKm.filter { it.isFinite() && it > 0 }.sorted()
    val size: Int get() = sorted.size

    /** Fração das ofertas anteriores com R$/km MENOR que [value] (0..1), ou nulo sem amostra. */
    fun percentile(value: Double?): Double? {
        if (value == null || sorted.size < minSamples) return null
        var lo = 0
        var hi = sorted.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (sorted[mid] < value) lo = mid + 1 else hi = mid
        }
        return lo.toDouble() / sorted.size
    }

    fun median(): Double? = if (sorted.size < minSamples) null else TimeCalibration.median(sorted)
}
