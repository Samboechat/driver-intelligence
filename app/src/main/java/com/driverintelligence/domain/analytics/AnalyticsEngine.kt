package com.driverintelligence.domain.analytics

import com.driverintelligence.domain.model.Classification
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/** Corrida REALIZADA (não confundir com oferta analisada). */
data class TripRecord(
    val id: Long,
    val startedAtMs: Long,
    val fare: Double,
    val totalKm: Double?,
    val totalMin: Double?,
    val fuelCost: Double?,
    val operationalCost: Double?,
    val estimatedProfit: Double?,
    val classification: Classification? = null,
)

data class SessionRecord(val startMs: Long, val endMs: Long)

data class PeriodSummary(
    val revenue: Double,
    /** Soma dos lucros estimados disponíveis. */
    val estimatedProfit: Double?,
    /** Algumas corridas não têm lucro estimado (custos não configurados). */
    val profitPartial: Boolean,
    val trips: Int,
    val km: Double,
    val rideMinutes: Double,
    val onlineMinutes: Double?,
    val fuelCost: Double,
    val operationalCost: Double,
    val revenuePerKm: Double?,
    val profitPerKm: Double?,
    /** Faturamento por hora em corrida (busca + viagem). */
    val revenuePerRideHour: Double?,
    /** Faturamento por hora online (sessões do assistente). */
    val revenuePerOnlineHour: Double?,
) {
    companion object {
        val EMPTY = PeriodSummary(0.0, null, false, 0, 0.0, 0.0, null, 0.0, 0.0, null, null, null, null)
    }
}

data class SeriesPoint(val start: LocalDate, val label: String, val revenue: Double, val profit: Double?, val trips: Int)

data class Bucket(
    /** 0..23 para horário; 1..7 (segunda..domingo) para dia da semana. */
    val key: Int,
    val label: String,
    val trips: Int,
    val revenue: Double,
    val minutes: Double,
    val profit: Double?,
) {
    val revenuePerHour: Double? get() = if (minutes > 0) revenue / (minutes / 60.0) else null
}

/**
 * Estatísticas a partir de dados reais armazenados. Não gera previsões:
 * quando a amostra é pequena, as funções de "melhores" retornam lista vazia.
 */
class AnalyticsEngine(private val zone: ZoneId = ZoneId.systemDefault()) {

    fun summary(trips: List<TripRecord>, sessions: List<SessionRecord>, fromMs: Long, toMs: Long): PeriodSummary {
        val inRange = trips.filter { it.startedAtMs in fromMs until toMs }
        val online = if (sessions.isEmpty()) null else sessions.sumOf { s ->
            val start = maxOf(s.startMs, fromMs)
            val end = minOf(s.endMs, toMs)
            if (end > start) (end - start) / 60_000.0 else 0.0
        }
        if (inRange.isEmpty()) return PeriodSummary.EMPTY.copy(onlineMinutes = online)

        val revenue = inRange.sumOf { it.fare }
        val withProfit = inRange.filter { it.estimatedProfit != null }
        val profit = if (withProfit.isEmpty()) null else withProfit.sumOf { it.estimatedProfit!! }
        val withKm = inRange.filter { it.totalKm != null && it.totalKm > 0 }
        val km = withKm.sumOf { it.totalKm!! }
        val revenueWithKm = withKm.sumOf { it.fare }
        val profitWithKm = withKm.filter { it.estimatedProfit != null }
        val withMin = inRange.filter { it.totalMin != null && it.totalMin > 0 }
        val minutes = withMin.sumOf { it.totalMin!! }
        val revenueWithMin = withMin.sumOf { it.fare }

        return PeriodSummary(
            revenue = revenue,
            estimatedProfit = profit,
            profitPartial = withProfit.size < inRange.size,
            trips = inRange.size,
            km = km,
            rideMinutes = minutes,
            onlineMinutes = online,
            fuelCost = inRange.sumOf { it.fuelCost ?: 0.0 },
            operationalCost = inRange.sumOf { it.operationalCost ?: 0.0 },
            revenuePerKm = if (km > 0) revenueWithKm / km else null,
            profitPerKm = if (profitWithKm.isNotEmpty()) {
                val k = profitWithKm.sumOf { it.totalKm!! }
                if (k > 0) profitWithKm.sumOf { it.estimatedProfit!! } / k else null
            } else null,
            revenuePerRideHour = if (minutes > 0) revenueWithMin / (minutes / 60.0) else null,
            revenuePerOnlineHour = if (online != null && online > 0) revenue / (online / 60.0) else null,
        )
    }

    fun dayRange(date: LocalDate): Pair<Long, Long> {
        val start = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        return start to end
    }

    fun dateOf(ms: Long): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    fun daily(trips: List<TripRecord>, endInclusive: LocalDate, days: Int): List<SeriesPoint> {
        val start = endInclusive.minusDays((days - 1).toLong())
        val byDate = trips.groupBy { dateOf(it.startedAtMs) }
        return (0 until days).map { i ->
            val d = start.plusDays(i.toLong())
            point(d, "${d.dayOfMonth}/${d.monthValue}", byDate[d].orEmpty())
        }
    }

    fun weekly(trips: List<TripRecord>, today: LocalDate, weeks: Int): List<SeriesPoint> {
        val thisWeek = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val byWeek = trips.groupBy { dateOf(it.startedAtMs).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)) }
        return (weeks - 1 downTo 0).map { i ->
            val w = thisWeek.minusWeeks(i.toLong())
            point(w, "${w.dayOfMonth}/${w.monthValue}", byWeek[w].orEmpty())
        }
    }

    fun monthly(trips: List<TripRecord>, today: LocalDate, months: Int): List<SeriesPoint> {
        val thisMonth = today.withDayOfMonth(1)
        val byMonth = trips.groupBy { dateOf(it.startedAtMs).withDayOfMonth(1) }
        return (months - 1 downTo 0).map { i ->
            val m = thisMonth.minusMonths(i.toLong())
            point(m, MONTHS[m.monthValue - 1], byMonth[m].orEmpty())
        }
    }

    fun byHourOfDay(trips: List<TripRecord>): List<Bucket> {
        val grouped = trips.groupBy { Instant.ofEpochMilli(it.startedAtMs).atZone(zone).hour }
        return (0..23).map { h -> bucket(h, "${h}h", grouped[h].orEmpty()) }
    }

    fun byWeekday(trips: List<TripRecord>): List<Bucket> {
        val grouped = trips.groupBy { dateOf(it.startedAtMs).dayOfWeek.value }
        return (1..7).map { d -> bucket(d, WEEKDAYS[d - 1], grouped[d].orEmpty()) }
    }

    /**
     * Melhores faixas por faturamento/hora. Exige [minSamples] corridas por faixa e
     * pelo menos duas faixas qualificadas para comparar; caso contrário, lista vazia.
     */
    fun best(buckets: List<Bucket>, minSamples: Int = 5, top: Int = 3): List<Bucket> {
        val qualified = buckets.filter { it.trips >= minSamples && it.revenuePerHour != null }
        if (qualified.size < 2) return emptyList()
        return qualified.sortedByDescending { it.revenuePerHour }.take(top)
    }

    fun progress(value: Double, goal: Double?): Double? =
        if (goal == null || goal <= 0) null else (value / goal).coerceAtLeast(0.0)

    private fun point(start: LocalDate, label: String, list: List<TripRecord>): SeriesPoint {
        val profits = list.mapNotNull { it.estimatedProfit }
        return SeriesPoint(
            start = start,
            label = label,
            revenue = list.sumOf { it.fare },
            profit = if (profits.isEmpty()) null else profits.sum(),
            trips = list.size,
        )
    }

    private fun bucket(key: Int, label: String, list: List<TripRecord>): Bucket {
        val profits = list.mapNotNull { it.estimatedProfit }
        val timed = list.filter { it.totalMin != null && it.totalMin > 0 }
        return Bucket(
            key = key,
            label = label,
            trips = list.size,
            revenue = timed.sumOf { it.fare },
            minutes = timed.sumOf { it.totalMin!! },
            profit = if (profits.isEmpty()) null else profits.sum(),
        )
    }

    companion object {
        val WEEKDAYS = listOf("Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom")
        val MONTHS = listOf("Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez")
    }
}
