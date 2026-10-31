package com.driverintelligence.domain.detection

import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.FrameAnalysis
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.recognition.OfferAnalyzer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OfferStateMachineTest {

    private val machine = OfferStateMachine(DetectionConfig(dedupWindowMs = 60_000))
    private val analyzer = OfferAnalyzer()
    private val ctx = AnalysisContext(costs = CostProfile(11.0, 6.2))

    private fun offer(fare: Double, confidence: Double): OfferAnalysis =
        analyzer.analyzeManual(OfferData(fare, 1.2, 9.3, 4.0, 20.0), ctx).copy(confidence = confidence)

    private fun frame(a: OfferAnalysis?, screen: Boolean = a != null) = FrameAnalysis(screen, a)

    private fun run(state: DetectionState, a: OfferAnalysis?, t: Long, screen: Boolean = a != null) =
        machine.reduce(state, DetectionEvent.FrameAnalyzed(frame(a, screen), t))

    @Test
    fun ociosoSemOferta_permaneceOcioso() {
        val tr = run(DetectionState(), null, 0)
        assertEquals(OfferPhase.IDLE, tr.state.phase)
        assertTrue(tr.effects.isEmpty())
    }

    @Test
    fun ofertaDeAltaConfianca_exibeERegistraNoPrimeiroFrame() {
        val a = offer(18.5, 0.95)
        val tr = run(DetectionState(), a, 0)
        assertEquals(OfferPhase.DISPLAYING, tr.state.phase)
        assertEquals(listOf(DetectionEffect.ShowOffer(a, changed = false), DetectionEffect.RecordAnalyzedOffer(a)), tr.effects)
    }

    @Test
    fun confiancaMedia_exigeConfirmacaoEmDoisFrames() {
        val a = offer(18.5, 0.7)
        val t1 = run(DetectionState(), a, 0)
        assertEquals(OfferPhase.OFFER_DETECTED, t1.state.phase)
        assertEquals(listOf(DetectionEffect.ShowReading(a)), t1.effects)
        val t2 = run(t1.state, a, 700)
        assertEquals(OfferPhase.DISPLAYING, t2.state.phase)
        assertTrue(t2.effects.first() is DetectionEffect.ShowOffer)
        assertTrue(t2.effects.any { it is DetectionEffect.RecordAnalyzedOffer })
    }

    @Test
    fun mesmaOferta_naoAtualizaOverlayRepetidamente() {
        val a = offer(18.5, 0.95)
        var s = run(DetectionState(), a, 0).state
        repeat(5) { i ->
            val tr = run(s, a, 700L * (i + 1))
            assertTrue(tr.effects.isEmpty())
            s = tr.state
        }
        assertEquals(OfferPhase.DISPLAYING, s.phase)
    }

    @Test
    fun mesmaOfertaComConfiancaMelhor_atualizaUmaVez() {
        val low = offer(18.5, 0.86)
        val high = low.copy(confidence = 1.0)
        val s = run(DetectionState(), low, 0).state
        val tr = run(s, high, 700)
        assertEquals(listOf(DetectionEffect.ShowOffer(high, changed = false)), tr.effects)
    }

    @Test
    fun ofertaMudou() {
        val a = offer(18.5, 0.95)
        val b = offer(22.0, 0.95)
        val s = run(DetectionState(), a, 0).state
        val tr = run(s, b, 700)
        assertEquals(OfferPhase.OFFER_CHANGED, tr.state.phase)
        assertEquals(DetectionEffect.ShowOffer(b, changed = true), tr.effects[0])
        assertEquals(DetectionEffect.RecordAnalyzedOffer(b), tr.effects[1])
    }

    @Test
    fun ofertaDispensada_aposDoisFramesSemOferta() {
        val a = offer(18.5, 0.95)
        val s = run(DetectionState(), a, 0).state
        val t1 = run(s, null, 700)
        assertTrue(t1.effects.isEmpty()) // tolera um frame ruim
        assertEquals(1, t1.state.missingFrames)
        val t2 = run(t1.state, null, 1400)
        assertEquals(OfferPhase.OFFER_DISMISSED, t2.state.phase)
        assertEquals(listOf(DetectionEffect.ClearOffer), t2.effects)
        assertNull(t2.state.current)
        val t3 = run(t2.state, null, 2100)
        assertEquals(OfferPhase.IDLE, t3.state.phase)
    }

    @Test
    fun leituraParcialDuranteExibicao_mantemOferta() {
        val a = offer(18.5, 0.95)
        val partial = analyzer.analyzeManual(OfferData(fare = 18.5), ctx)
        var s = run(DetectionState(), a, 0).state
        repeat(4) { i ->
            val tr = run(s, partial, 700L * (i + 1), screen = true)
            assertTrue(tr.effects.isEmpty())
            s = tr.state
        }
        assertEquals(a, s.current)
    }

    @Test
    fun telaDeOfertaIncompleta_mostraLendoUmaVezSemPiscar() {
        val partial = analyzer.analyzeManual(OfferData(fare = 18.5), ctx)
        val t1 = run(DetectionState(), partial, 0, screen = true)
        assertEquals(OfferPhase.SCREEN_DETECTED, t1.state.phase)
        assertEquals(1, t1.effects.size)
        var s = t1.state
        repeat(4) { i ->
            val tr = run(s, partial, 700L * (i + 1), screen = true)
            assertTrue(tr.effects.isEmpty())
            s = tr.state
        }
    }

    @Test
    fun deduplicacao_naoRegistraDuasVezesNaJanela() {
        val a = offer(18.5, 0.95)
        var s = run(DetectionState(), a, 0).state
        s = run(s, null, 700).state
        s = run(s, null, 1400).state // dispensada
        val again = run(s, a, 10_000)
        assertTrue(again.effects.any { it is DetectionEffect.ShowOffer })
        assertTrue(again.effects.none { it is DetectionEffect.RecordAnalyzedOffer })

        var s2 = run(again.state, null, 10_700).state
        s2 = run(s2, null, 11_400).state
        val later = run(s2, a, 80_000)
        assertTrue(later.effects.any { it is DetectionEffect.RecordAnalyzedOffer })
    }

    @Test
    fun erro_emiteUmaVezERecupera() {
        val t1 = machine.reduce(DetectionState(), DetectionEvent.ProcessingFailed("falha", 0))
        assertEquals(OfferPhase.ERROR, t1.state.phase)
        assertEquals(listOf(DetectionEffect.ShowError("falha")), t1.effects)
        val t2 = machine.reduce(t1.state, DetectionEvent.ProcessingFailed("falha", 700))
        assertTrue(t2.effects.isEmpty())
        val t3 = run(t2.state, offer(18.5, 0.95), 1400)
        assertEquals(OfferPhase.DISPLAYING, t3.state.phase)
    }

    @Test
    fun reset_limpaOferta() {
        val s = run(DetectionState(), offer(18.5, 0.95), 0).state
        val tr = machine.reduce(s, DetectionEvent.Reset)
        assertEquals(OfferPhase.IDLE, tr.state.phase)
        assertEquals(listOf(DetectionEffect.ClearOffer), tr.effects)
        assertEquals(s.recentlyRecorded, tr.state.recentlyRecorded)
    }
}
