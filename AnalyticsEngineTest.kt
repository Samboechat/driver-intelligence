package com.driverintelligence.domain.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class AnalyticsEngineTest {

    private val zone = ZoneId.of("America/Sao_Paulo")
    private val engine = AnalyticsEngine(zone)
    private val day = LocalDate.of(2026, 10, 28) // quarta-feira

    private fun at(date: LocalDate, hour: Int, minute: Int = 0) =
        LocalDateTime.of(date, java.time.LocalTime.of(hour, minute)).atZone(zone).toInstant().toEpochMilli()

    private fun trip(id: Long, ms: Long, fare: Double, km: Double?, min: Double?, profit: Double?, fuel: Double? = null) =
        TripRecord(id, ms, fare, km, min, fuel, null, profit)

    @Test
    fun resumoDoPeriodo() {
        val trips = listOf(
            trip(1, at(day, 8), 20.0, 10.0, 25.0, 14.0, 5.0),
            trip(2, at(day, 9), 30.0, 15.0, 35.0, 20.0, 7.0),
            trip(3, at(day.minusDays(1), 9), 99.0, 10.0, 20.0, 50.0), // fora do dia
        )
        val (from, to) = engine.dayRange(day)
        val s = engine.summary(trips, emptyList(), from, to)
        assertEquals(2, s.trips)
        assertEquals(50.0, s.revenue, 1e-9)
        assertEquals(34.0, s.estimatedProfit!!, 1e-9)
        assertEquals(25.0, s.km, 1e-9)
        assertEquals(2.0, s.revenuePerKm!!, 1e-9)
        assertEquals(50.0, s.revenuePerRideHour!!, 1e-9)
        assertEquals(12.0, s.fuelCost, 1e-9)
        assertNull(s.onlineMinutes)
        assertTrue(!s.profitPartial)
    }

    @Test
    fun lucroParcialQuandoAlgumaCorridaNaoTemCusto() {
        val trips = listOf(trip(1, at(day, 8), 20.0, 10.0, 25.0, 14.0), trip(2, at(day, 9), 30.0, 15.0, 35.0, null))
        val (from, to) = engine.dayRange(day)
        val s = engine.summary(trips, emptyList(), from, to)
        assertTrue(s.profitPartial)
        assertEquals(14.0, s.estimatedProfit!!, 1e-9)
    }

    @Test
    fun tempoOnline_recortadoPeloPeriodo() {
        val (from, to) = engine.dayRange(day)
        val sessions = listOf(
            SessionRecord(at(day, 7), at(day, 9)), // 120 min
            SessionRecord(at(day.minusDays(1), 23), at(day, 1)), // 60 min dentro do dia
        )
        val s = engine.summary(listOf(trip(1, at(day, 8), 90.0, 30.0, 60.0, 50.0)), sessions, from, to)
        assertEquals(180.0, s.onlineMinutes!!, 1e-9)
        assertEquals(30.0, s.revenuePerOnlineHour!!, 1e-9)
    }

    @Test
    fun periodoVazio() {
        val (from, to) = engine.dayRange(day)
        val s = engine.summary(emptyList(), emptyList(), from, to)
        assertEquals(0, s.trips)
        assertNull(s.revenuePerKm)
    }

    @Test
    fun serieDiariaInclusiveDiasSemCorrida() {
        val trips = listOf(trip(1, at(day, 8), 20.0, 10.0, 25.0, 14.0), trip(2, at(day.minusDays(2), 8), 10.0, 5.0, 10.0, null))
        val series = engine.daily(trips, day, 7)
        assertEquals(7, series.size)
        assertEquals(day, series.last().start)
        assertEquals(20.0, series.last().revenue, 1e-9)
        assertEquals(0.0, series[5].revenue, 1e-9)
        assertNull(series[4].profit)
        assertEquals(10.0, series[4].revenue, 1e-9)
    }

    @Test
    fun seriesSemanalEMensal() {
        val trips = listOf(trip(1, at(day, 8), 20.0, 10.0, 25.0, 14.0), trip(2, at(day.minusWeeks(1), 8), 10.0, 5.0, 10.0, 5.0))
        val weeks = engine.weekly(trips, day, 4)
        assertEquals(4, weeks.size)
        assertEquals(LocalDate.of(2026, 10, 26), weeks.last().start)
        assertEquals(20.0, weeks.last().revenue, 1e-9)
        assertEquals(10.0, weeks[2].revenue, 1e-9)
        val months = engine.monthly(trips, day, 3)
        assertEquals("Out", months.last().label)
        assertEquals(30.0, months.last().revenue, 1e-9)
    }

    @Test
    fun porHorarioEDiaDaSemana() {
        val trips = listOf(trip(1, at(day, 8), 20.0, 10.0, 30.0, 14.0), trip(2, at(day, 8, 40), 10.0, 5.0, 30.0, 5.0))
        val hours = engine.byHourOfDay(trips)
        assertEquals(24, hours.size)
        assertEquals(2, hours[8].trips)
        assertEquals(30.0, hours[8].revenuePerHour!!, 1e-9)
        val days = engine.byWeekday(trips)
        assertEquals(2, days[2].trips) // quarta
        assertEquals("Qua", days[2].label)
    }

    @Test
    fun melhoresHorarios_exigemAmostraMinima() {
        val few = (1..4).map { trip(it.toLong(), at(day, 8), 20.0, 10.0, 30.0, 10.0) }
        assertTrue(engine.best(engine.byHourOfDay(few)).isEmpty())

        val many = (1..6).map { trip(it.toLong(), at(day.minusDays(it.toLong()), 8), 30.0, 10.0, 30.0, 10.0) } +
            (1..6).map { trip(100L + it, at(day.minusDays(it.toLong()), 14), 15.0, 10.0, 30.0, 5.0) }
        val best = engine.best(engine.byHourOfDay(many))
        assertEquals(2, best.size)
        assertEquals(8, best.first().key)
    }

    @Test
    fun progressoDaMeta() {
        assertEquals(0.5, engine.progress(100.0, 200.0)!!, 1e-9)
        assertNull(engine.progress(100.0, null))
        assertNull(engine.progress(100.0, 0.0))
    }
}
