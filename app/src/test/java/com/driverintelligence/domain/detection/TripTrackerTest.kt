package com.driverintelligence.domain.detection

import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OcrFrame
import com.driverintelligence.domain.recognition.OfferAnalyzer
import com.driverintelligence.domain.recognition.ScreenClassifier
import com.driverintelligence.domain.recognition.ScreenKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TripTrackerTest {

    private val tracker = TripTracker()
    private val offer = OfferAnalyzer().analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), AnalysisContext(costs = CostProfile(11.0, 6.2)))
    private val other = OfferAnalyzer().analyzeManual(OfferData(25.0, 2.0, 12.0, 6.0, 25.0), AnalysisContext())

    private class Run(val tracker: TripTracker) {
        var state = TrackerState()
        val effects = mutableListOf<TrackerEffect>()
        fun send(e: TrackerEvent) {
            val tr = tracker.reduce(state, e)
            state = tr.state
            effects += tr.effects
        }
        fun see(kind: ScreenKind, at: Long, o: com.driverintelligence.domain.recognition.OfferAnalysis? = null) =
            send(TrackerEvent.Observe(kind, o, at))
        inline fun <reified T : TrackerEffect> all() = effects.filterIsInstance<T>()
    }

    private fun min(m: Double) = (m * 60_000).toLong()

    @Test
    fun fluxoCompleto_aceiteBuscaEsperaViagemConclusao() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.OFFER, 1_000, offer)
        // Aceitou: tela de busca aparece em 2 frames seguidos.
        r.see(ScreenKind.GOING_TO_PICKUP, 3_000)
        r.see(ScreenKind.GOING_TO_PICKUP, 4_000)
        val decided = r.all<TrackerEffect.OutcomeDecided>().single()
        assertEquals(OfferOutcome.ACCEPTED, decided.outcome)
        assertEquals(TripPhase.TO_PICKUP, r.state.phase)
        assertEquals(3_000L, r.state.timeline!!.acceptedAt)

        // Chegou ao passageiro após 7 minutos (a oferta dizia 4).
        r.see(ScreenKind.WAITING_PASSENGER, 3_000 + min(7.0))
        r.see(ScreenKind.WAITING_PASSENGER, 4_000 + min(7.0))
        assertEquals(TripPhase.WAITING, r.state.phase)
        // Iniciou a viagem 2 minutos depois.
        val start = 3_000 + min(9.0)
        r.see(ScreenKind.ON_TRIP, start)
        r.see(ScreenKind.ON_TRIP, start + 1_000)
        assertEquals(TripPhase.ON_TRIP, r.state.phase)
        // Concluiu 26 minutos depois.
        r.see(ScreenKind.TRIP_COMPLETED, start + min(26.0))

        val done = r.all<TrackerEffect.TripFinished>().single().timeline
        assertEquals(7.0, done.actualPickupMin!!, 0.01)
        assertEquals(26.0, done.actualTripMin!!, 0.01)
        assertEquals(TripPhase.NONE, r.state.phase)
    }

    @Test
    fun recusa_ofertaSomeRapidoEVoltaParaProcurar() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.OFFER, 2_000, offer)
        r.see(ScreenKind.ONLINE_IDLE, 3_000)
        r.see(ScreenKind.ONLINE_IDLE, 4_000)
        assertEquals(OfferOutcome.REJECTED, r.all<TrackerEffect.OutcomeDecided>().single().outcome)
        assertNull(r.state.timeline)
    }

    @Test
    fun ignorada_ofertaFicouAteOTempoAcabar() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.OFFER, 14_000, offer)
        r.see(ScreenKind.ONLINE_IDLE, 15_000)
        r.see(ScreenKind.ONLINE_IDLE, 16_000)
        assertEquals(OfferOutcome.EXPIRED, r.all<TrackerEffect.OutcomeDecided>().single().outcome)
    }

    @Test
    fun leituraIsoladaNaoDecide() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.ONLINE_IDLE, 1_000)
        r.see(ScreenKind.OFFER, 2_000, offer)
        assertTrue(r.all<TrackerEffect.OutcomeDecided>().isEmpty())
        assertEquals(TripPhase.OFFER, r.state.phase)
    }

    @Test
    fun outraOfertaSubstitui_aAnteriorFoiRecusada() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.OFFER, 5_000, other)
        val d = r.all<TrackerEffect.OutcomeDecided>().single()
        assertEquals(offer.fingerprint, d.offer.fingerprint)
        assertEquals(OfferOutcome.REJECTED, d.outcome)
        assertEquals(other.fingerprint, r.state.offer!!.fingerprint)
    }

    @Test
    fun cancelamento_voltaAProcurarSemIniciar() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.GOING_TO_PICKUP, 1_000)
        r.see(ScreenKind.GOING_TO_PICKUP, 2_000)
        repeat(3) { r.see(ScreenKind.ONLINE_IDLE, 60_000L + it * 1_000) }
        assertEquals(1, r.all<TrackerEffect.TripCancelled>().size)
        assertTrue(r.all<TrackerEffect.TripFinished>().isEmpty())
    }

    @Test
    fun fimDaViagemSemTelaDeConclusao_voltaParaOnline() {
        val r = Run(tracker)
        r.send(TrackerEvent.ManualAccept(offer, 0))
        r.see(ScreenKind.ON_TRIP, min(5.0))
        r.see(ScreenKind.ON_TRIP, min(5.0) + 1_000)
        r.see(ScreenKind.ONLINE_IDLE, min(30.0))
        r.see(ScreenKind.ONLINE_IDLE, min(30.0) + 1_000)
        val done = r.all<TrackerEffect.TripFinished>().single().timeline
        assertEquals(5.0, done.actualPickupMin!!, 0.01)
        assertEquals(25.0, done.actualTripMin!!, 0.01)
        assertEquals(OutcomeSource.MANUAL, done.acceptSource)
    }

    @Test
    fun ofertaDuranteAViagem_naoEncerraACorrida() {
        val r = Run(tracker)
        r.send(TrackerEvent.ManualAccept(offer, 0))
        r.see(ScreenKind.ON_TRIP, 1_000)
        r.see(ScreenKind.ON_TRIP, 2_000)
        r.see(ScreenKind.OFFER, 3_000, other)
        r.see(ScreenKind.OFFER, 4_000, other)
        assertEquals(TripPhase.ON_TRIP, r.state.phase)
        assertTrue(r.all<TrackerEffect.TripFinished>().isEmpty())
    }

    @Test
    fun botoesManuais_recusarEFinalizar() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.send(TrackerEvent.ManualReject(1_000))
        assertEquals(OutcomeSource.MANUAL, r.all<TrackerEffect.OutcomeDecided>().single().source)

        val r2 = Run(tracker)
        r2.send(TrackerEvent.ManualAccept(offer, 0))
        r2.send(TrackerEvent.ManualFinish(min(20.0)))
        val done = r2.all<TrackerEffect.TripFinished>().single().timeline
        assertEquals(20.0, done.totalMin!!, 0.01)
    }

    @Test
    fun semLeituraPorMuitoTempo_resultadoDesconhecido() {
        val r = Run(tracker)
        r.see(ScreenKind.OFFER, 0, offer)
        r.see(ScreenKind.UNKNOWN, 30_000)
        assertEquals(OfferOutcome.UNKNOWN, r.all<TrackerEffect.OutcomeDecided>().single().outcome)
    }

    @Test
    fun classificadorDeTelas() {
        fun k(text: String, offer: Boolean = false) = ScreenClassifier.classify(OcrFrame.fromText(text), offer)
        assertEquals(ScreenKind.OFFER, k("qualquer", offer = true))
        assertEquals(ScreenKind.ONLINE_IDLE, k("Você está online\nProcurando viagens"))
        assertEquals(ScreenKind.OFFLINE, k("Você está offline"))
        assertEquals(ScreenKind.GOING_TO_PICKUP, k("A caminho do passageiro\n5 min · 1,8 km\nCheguei"))
        assertEquals(ScreenKind.WAITING_PASSENGER, k("Aguardando o passageiro\nIniciar viagem"))
        assertEquals(ScreenKind.ON_TRIP, k("Levando Maria\nFinalizar viagem"))
        assertEquals(ScreenKind.TRIP_COMPLETED, k("Viagem concluída\nVocê ganhou R$ 18,50"))
        assertEquals(ScreenKind.UNKNOWN, k("Configurações da conta"))
    }
}
