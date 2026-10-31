package com.driverintelligence.domain.analytics

import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OfferAnalyzer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class TimeCalibrationTest {

    private val zone = ZoneId.of("America/Sao_Paulo")
    private fun at(day: Int, hour: Int) = LocalDateTime.of(2026, 10, day, hour, 0).atZone(zone).toInstant().toEpochMilli()

    private fun sample(day: Int, hour: Int, pickupRatio: Double, tripRatio: Double) =
        TimingSample(at(day, hour), 4.0, 4.0 * pickupRatio, 20.0, 20.0 * tripRatio)

    @Test
    fun semAmostras_usaPadrao() {
        val f = TimeCalibration(emptyList(), 1.35, 1.15, zone).factorsAt(8)
        assertEquals(1.35, f.pickup, 1e-9)
        assertEquals(1.15, f.trip, 1e-9)
        assertEquals(FactorSource.DEFAULT, f.pickupSource)
        assertFalse(f.isLearned)
    }

    @Test
    fun aprendeComMedianaResistenteAOutliers() {
        val samples = listOf(1.5, 1.6, 1.7, 1.8, 4.9).mapIndexed { i, r -> sample(i + 1, 14, r, 1.1) }
        val f = TimeCalibration(samples, zone = zone).factorsAt(3) // horário sem amostras próximas
        assertEquals(1.7, f.pickup, 1e-9)
        assertEquals(1.1, f.trip, 1e-9)
        assertEquals(FactorSource.LEARNED, f.pickupSource)
        assertEquals(5, f.pickupSamples)
    }

    @Test
    fun horarioDePico_usaAmostrasDoMesmoHorario() {
        val rush = (1..5).map { sample(it, 18, 2.0, 1.4) }
        val calm = (6..15).map { sample(it, 10, 1.2, 1.05) }
        val cal = TimeCalibration(rush + calm, zone = zone)
        val f18 = cal.factorsAt(18)
        assertEquals(2.0, f18.pickup, 1e-9)
        assertEquals(FactorSource.LEARNED_HOUR, f18.pickupSource)
        val f10 = cal.factorsAt(10)
        assertEquals(1.2, f10.pickup, 1e-9)
    }

    @Test
    fun ignoraAmostrasInvalidas() {
        val bad = listOf(
            TimingSample(at(1, 8), 0.5, 5.0, 20.0, 22.0), // oferta < 1 min
            TimingSample(at(2, 8), 4.0, 40.0, 20.0, 22.0), // razão 10x
            TimingSample(at(3, 8), null, 5.0, 20.0, 22.0),
        )
        val f = TimeCalibration(bad, zone = zone).overall()
        assertEquals(0, f.pickupSamples)
        assertEquals(FactorSource.DEFAULT, f.pickupSource)
    }

    @Test
    fun analisador_usaTempoRealistaNaClassificacao() {
        // Pelo tempo do app (24 min) a corrida é verde; com busca 2,5x e viagem 1,6x fica abaixo da meta por hora.
        val samples = (1..6).map { sample(it, 3, 2.5, 1.6) }
        val ctx = AnalysisContext(costs = CostProfile(11.0, 6.2), goals = Goals(minRevenuePerHour = 40.0), calibration = TimeCalibration(samples, zone = zone))
        val analyzer = OfferAnalyzer(hourNow = { 3 })
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), ctx)
        assertTrue(a.usedRealistic)
        assertEquals(46.25, a.financial.revenuePerHour!!, 1e-6)
        assertEquals(18.5 / ((10.0 + 32.0) / 60.0), a.realistic!!.revenuePerHour!!, 1e-6)
        assertTrue(a.decision.classification != Classification.GREEN)

        val semAjuste = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), ctx.copy(useRealisticTime = false))
        assertEquals(Classification.GREEN, semAjuste.decision.classification)
        assertFalse(semAjuste.usedRealistic)
    }

    @Test
    fun comparativo_percentilSoComAmostraMinima() {
        assertNull(OfferBenchmark(listOf(1.0, 2.0)).percentile(1.5))
        val b = OfferBenchmark((1..20).map { it / 10.0 }) // 0,1 .. 2,0
        assertEquals(0.5, b.percentile(1.05)!!, 1e-9)
        assertEquals(1.0, b.percentile(5.0)!!, 1e-9)
        assertEquals(0.0, b.percentile(0.05)!!, 1e-9)
        val a = OfferAnalyzer().analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), AnalysisContext(benchmark = b))
        assertEquals(17.0 / 20.0, a.percentile!!, 1e-9) // 1,76/km > 17 das 20 ofertas
    }
}
