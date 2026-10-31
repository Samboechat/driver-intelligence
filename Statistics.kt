package com.driverintelligence.features.statistics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.SessionRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.designsystem.BarChart
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.LineChart
import com.driverintelligence.designsystem.LinearMeter
import com.driverintelligence.designsystem.MetricTile
import com.driverintelligence.designsystem.SegmentedSelector
import com.driverintelligence.domain.analytics.AnalyticsEngine
import com.driverintelligence.domain.analytics.Bucket
import com.driverintelligence.domain.analytics.PeriodSummary
import com.driverintelligence.domain.analytics.SeriesPoint
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.ScreenList
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters
import javax.inject.Inject

enum class StatsPeriod(val label: String, val days: Int) { WEEK("7 dias", 7), MONTH("30 dias", 30), QUARTER("90 dias", 90) }

data class GoalProgress(val label: String, val value: Double, val goal: Double)

data class StatsUiState(
    val period: StatsPeriod = StatsPeriod.MONTH,
    val summary: PeriodSummary = PeriodSummary.EMPTY,
    val daily: List<SeriesPoint> = emptyList(),
    val weekly: List<SeriesPoint> = emptyList(),
    val monthly: List<SeriesPoint> = emptyList(),
    val byHour: List<Bucket> = emptyList(),
    val byWeekday: List<Bucket> = emptyList(),
    val bestHours: List<Bucket> = emptyList(),
    val bestDays: List<Bucket> = emptyList(),
    val goals: List<GoalProgress> = emptyList(),
    val offersAnalyzed: Int = 0,
    val offersByClass: Map<Classification, Int> = emptyMap(),
    val offersRegistered: Int = 0,
)

@HiltViewModel
class StatisticsViewModel @Inject constructor(
    trips: TripRepository,
    offers: OfferRepository,
    sessions: SessionRepository,
    settings: SettingsRepository,
    private val analytics: AnalyticsEngine,
) : ViewModel() {
    private val period = MutableStateFlow(StatsPeriod.MONTH)

    val state: StateFlow<StatsUiState> = combine(period, trips.trips, offers.all, sessions.sessions, settings.settings) { p, t, o, s, st ->
        val today = LocalDate.now()
        val start = today.minusDays((p.days - 1).toLong())
        val (from, _) = analytics.dayRange(start)
        val (_, to) = analytics.dayRange(today)
        val all = t.map { it.toRecord() }
        val inPeriod = all.filter { it.startedAtMs in from until to }
        val hours = analytics.byHourOfDay(inPeriod)
        val days = analytics.byWeekday(inPeriod)
        val offersIn = o.filter { it.detectedAt in from until to }
        StatsUiState(
            period = p,
            summary = analytics.summary(all, s, from, to),
            daily = analytics.daily(all, today, p.days.coerceAtMost(30)),
            weekly = analytics.weekly(all, today, 8),
            monthly = analytics.monthly(all, today, 6),
            byHour = hours,
            byWeekday = days,
            bestHours = analytics.best(hours),
            bestDays = analytics.best(days, minSamples = 5),
            goals = goalProgress(all, st.goals, today),
            offersAnalyzed = offersIn.size,
            offersByClass = offersIn.groupingBy { it.classification }.eachCount(),
            offersRegistered = offersIn.count { it.isRegistered },
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), StatsUiState())

    fun setPeriod(p: StatsPeriod) {
        period.value = p
    }

    private fun goalProgress(all: List<com.driverintelligence.domain.analytics.TripRecord>, goals: Goals, today: LocalDate): List<GoalProgress> {
        fun sumBetween(start: LocalDate, endInclusive: LocalDate): Double {
            val (from, _) = analytics.dayRange(start)
            val (_, to) = analytics.dayRange(endInclusive)
            return all.filter { it.startedAtMs in from until to }.sumOf { it.fare }
        }
        fun profitBetween(start: LocalDate): Double {
            val (from, to) = analytics.dayRange(start)
            return all.filter { it.startedAtMs in from until to }.sumOf { it.estimatedProfit ?: 0.0 }
        }
        return buildList {
            goals.dailyRevenue?.let { add(GoalProgress("Faturamento de hoje", sumBetween(today, today), it)) }
            goals.dailyProfit?.let { add(GoalProgress("Lucro estimado de hoje", profitBetween(today), it)) }
            goals.weeklyRevenue?.let { add(GoalProgress("Faturamento da semana", sumBetween(today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)), today), it)) }
            goals.monthlyRevenue?.let { add(GoalProgress("Faturamento do mês", sumBetween(today.withDayOfMonth(1), today), it)) }
        }
    }
}

@Composable
fun StatisticsScreen(vm: StatisticsViewModel = hiltViewModel()) {
    val s by vm.state.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    val sum = s.summary

    ScreenList(title = "Estatísticas", subtitle = "Somente dados registrados no aparelho") {
        item { SegmentedSelector(StatsPeriod.entries, s.period, { it.label }, vm::setPeriod) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricTile("Faturamento", Br.money(sum.revenue), Modifier.weight(1f), caption = "${sum.trips} corridas")
                MetricTile("Lucro operacional", Br.money(sum.estimatedProfit), Modifier.weight(1f), caption = if (sum.profitPartial) "estimativa parcial" else "estimado", valueColor = sum.estimatedProfit?.let { if (it >= 0) c.positive else c.negative })
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricTile("Média/km", Br.perKm(sum.revenuePerKm), Modifier.weight(1f), caption = "lucro ${Br.perKm(sum.profitPerKm)}")
                MetricTile("Média/hora", Br.perHour(sum.revenuePerRideHour), Modifier.weight(1f), caption = sum.revenuePerOnlineHour?.let { "online ${Br.perHour(it)}" } ?: "em corrida")
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricTile("Custos acumulados", Br.money(sum.fuelCost + sum.operationalCost), Modifier.weight(1f), caption = "combustível ${Br.money(sum.fuelCost)}", estimated = true)
                MetricTile("Quilômetros", Br.km(sum.km, 0), Modifier.weight(1f), caption = Br.minutes(sum.rideMinutes) + " em corrida")
            }
        }

        if (s.goals.isNotEmpty()) {
            item {
                DiCard {
                    Text("Desempenho em relação às metas", style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
                    s.goals.forEach { g ->
                        Spacer(Modifier.height(10.dp))
                        InfoRow(g.label, "${Br.money(g.value)} de ${Br.money(g.goal)}")
                        val p = (g.value / g.goal).toFloat()
                        LinearMeter(p, color = if (p >= 1f) c.positive else c.brand)
                    }
                }
            }
        }

        item {
            ChartCard("Faturamento diário", "Barra interna: lucro estimado") {
                BarChart(s.daily.map { it.revenue }, s.daily.map { it.label }, secondary = s.daily.map { it.profit }, labelEvery = if (s.daily.size > 10) 5 else 1, description = "Faturamento diário")
            }
        }
        item {
            ChartCard("Lucro por dia", "Lucro operacional estimado") {
                BarChart(s.daily.map { it.profit ?: 0.0 }, s.daily.map { it.label }, color = c.positive, labelEvery = if (s.daily.size > 10) 5 else 1, description = "Lucro por dia")
            }
        }
        item {
            ChartCard("Evolução semanal", "Faturamento das últimas 8 semanas") {
                LineChart(s.weekly.map { it.revenue }, s.weekly.map { it.label }, labelEvery = 2, description = "Evolução semanal")
            }
        }
        item {
            ChartCard("Evolução mensal", "Faturamento dos últimos 6 meses") {
                BarChart(s.monthly.map { it.revenue }, s.monthly.map { it.label }, secondary = s.monthly.map { it.profit }, description = "Evolução mensal")
            }
        }
        item {
            ChartCard("Rentabilidade por horário", "Faturamento por hora em corrida, por hora de início") {
                BarChart(s.byHour.map { it.revenuePerHour ?: 0.0 }, s.byHour.map { "${it.key}" }, labelEvery = 3, valueFormatter = { Br.perHour(it) }, description = "Rentabilidade por horário")
            }
        }
        item {
            ChartCard("Rentabilidade por dia da semana", "Faturamento por hora em corrida") {
                BarChart(s.byWeekday.map { it.revenuePerHour ?: 0.0 }, s.byWeekday.map { it.label }, valueFormatter = { Br.perHour(it) }, description = "Rentabilidade por dia da semana")
            }
        }
        item {
            DiCard {
                Text("Análises operacionais", style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
                Spacer(Modifier.height(8.dp))
                if (s.bestHours.isEmpty()) {
                    Text("Melhores horários: dados insuficientes (mínimo de 5 corridas por faixa horária, em pelo menos 2 faixas).", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                } else {
                    InfoRow("Melhores horários", s.bestHours.joinToString(" · ") { "${it.label} (${Br.perHour(it.revenuePerHour)})" })
                }
                if (s.bestDays.isEmpty()) {
                    Text("Dias mais rentáveis: dados insuficientes (mínimo de 5 corridas por dia da semana).", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                } else {
                    InfoRow("Dias mais rentáveis", s.bestDays.joinToString(" · ") { it.label })
                }
                Spacer(Modifier.height(8.dp))
                InfoRow("Ofertas analisadas no período", s.offersAnalyzed.toString())
                if (s.offersAnalyzed > 0) {
                    Classification.entries.forEach { cl ->
                        val n = s.offersByClass[cl] ?: 0
                        if (n > 0) InfoRow("  ${cl.label}", "$n (${Br.percent(n.toDouble() / s.offersAnalyzed)})", valueColor = c.of(cl))
                    }
                    InfoRow("Registradas como realizadas", "${s.offersRegistered} (${Br.percent(s.offersRegistered.toDouble() / s.offersAnalyzed)})")
                }
            }
        }
    }
}

@Composable
private fun ChartCard(title: String, subtitle: String, content: @Composable () -> Unit) {
    val c = DiTheme.colors
    DiCard {
        Text(title, style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        Spacer(Modifier.height(12.dp))
        content()
    }
}
