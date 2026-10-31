package com.driverintelligence.domain.detection

import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.recognition.ScreenKind

enum class OfferOutcome(val label: String, val shortLabel: String) {
    ACCEPTED("Aceita", "ACEITA"),
    REJECTED("Recusada", "RECUSADA"),
    EXPIRED("Não respondida (tempo esgotou)", "IGNORADA"),
    UNKNOWN("Sem confirmação", "?"),
}

enum class OutcomeSource(val label: String) { DETECTED("detectado na tela"), MANUAL("informado por você") }

enum class TripPhase(val label: String) {
    NONE("Sem corrida"),
    OFFER("Oferta na tela"),
    TO_PICKUP("Indo buscar"),
    WAITING("Aguardando passageiro"),
    ON_TRIP("Em viagem"),
}

/** Linha do tempo real de uma corrida aceita. */
data class TripTimeline(
    val offer: OfferAnalysis,
    val acceptedAt: Long,
    val arrivedAt: Long? = null,
    val startedAt: Long? = null,
    val completedAt: Long? = null,
    val acceptSource: OutcomeSource = OutcomeSource.DETECTED,
) {
    /** Minutos reais do aceite até chegar ao passageiro (ou até iniciar a viagem). */
    val actualPickupMin: Double?
        get() = (arrivedAt ?: startedAt)?.let { (it - acceptedAt).coerceAtLeast(0) / 60_000.0 }

    /** Minutos reais com o passageiro. */
    val actualTripMin: Double?
        get() = if (startedAt != null && completedAt != null) (completedAt - startedAt).coerceAtLeast(0) / 60_000.0 else null

    val totalMin: Double?
        get() = completedAt?.let { (it - acceptedAt).coerceAtLeast(0) / 60_000.0 }
}

data class TrackerConfig(
    /** Frames iguais e seguidos para confirmar uma mudança de tela (evita leituras isoladas erradas). */
    val stableFrames: Int = 2,
    /** Oferta visível por mais que isso e depois sumiu sem aceite: tempo esgotou. */
    val expireAfterMs: Long = 13_000,
    /** Sem conseguir ler a tela por esse tempo após a oferta: resultado desconhecido. */
    val unknownAfterMs: Long = 25_000,
    /** Corrida aberta há mais que isso é descartada (detecção perdeu o fim). */
    val maxTripMs: Long = 4 * 60 * 60_000L,
)

data class TrackerState(
    val phase: TripPhase = TripPhase.NONE,
    val offer: OfferAnalysis? = null,
    val offerShownAt: Long = 0,
    val offerLastSeenAt: Long = 0,
    val timeline: TripTimeline? = null,
    val pendingKind: ScreenKind? = null,
    val pendingCount: Int = 0,
    val pendingSince: Long = 0,
) {
    val isTripActive: Boolean get() = timeline != null
}

sealed interface TrackerEvent {
    /** Um frame lido. [offer] é a oferta confirmada/exibida no momento (se houver). */
    data class Observe(val kind: ScreenKind, val offer: OfferAnalysis?, val at: Long) : TrackerEvent
    data class ManualAccept(val offer: OfferAnalysis, val at: Long) : TrackerEvent
    data class ManualReject(val at: Long) : TrackerEvent
    data class ManualFinish(val at: Long) : TrackerEvent
    data class ManualCancel(val at: Long) : TrackerEvent
    data object Reset : TrackerEvent
}

sealed interface TrackerEffect {
    data class OutcomeDecided(val offer: OfferAnalysis, val outcome: OfferOutcome, val source: OutcomeSource, val at: Long) : TrackerEffect
    data class PhaseChanged(val phase: TripPhase, val timeline: TripTimeline?) : TrackerEffect
    data class TripFinished(val timeline: TripTimeline) : TrackerEffect
    data class TripCancelled(val timeline: TripTimeline) : TrackerEffect
}

data class TrackerTransition(val state: TrackerState, val effects: List<TrackerEffect> = emptyList())

/**
 * Entende o que o motorista fez com a oferta e acompanha a corrida aceita:
 *
 *   oferta → (tela de busca/espera/viagem) → ACEITA → indo buscar → aguardando → em viagem → concluída
 *   oferta → (tela "procurando viagens")   → RECUSADA (ou IGNORADA, se ficou até o tempo acabar)
 *
 * Puro e determinístico. Os botões do overlay (Aceitei/Recusei/Finalizar/Cancelada) corrigem a detecção.
 */
class TripTracker(private val config: TrackerConfig = TrackerConfig()) {

    fun reduce(s: TrackerState, e: TrackerEvent): TrackerTransition = when (e) {
        TrackerEvent.Reset -> TrackerTransition(TrackerState())
        is TrackerEvent.ManualAccept -> accept(s.copy(offer = e.offer, offerShownAt = if (s.offer?.fingerprint == e.offer.fingerprint) s.offerShownAt else e.at), e.at, OutcomeSource.MANUAL, TripPhase.TO_PICKUP)
        is TrackerEvent.ManualReject -> {
            val offer = s.offer
            if (s.phase == TripPhase.OFFER && offer != null) {
                TrackerTransition(
                    TrackerState(),
                    listOf(TrackerEffect.OutcomeDecided(offer, OfferOutcome.REJECTED, OutcomeSource.MANUAL, e.at), TrackerEffect.PhaseChanged(TripPhase.NONE, null)),
                )
            } else TrackerTransition(s)
        }
        is TrackerEvent.ManualFinish -> s.timeline?.let { finish(it, e.at) } ?: TrackerTransition(s)
        is TrackerEvent.ManualCancel -> s.timeline?.let { cancel(it) } ?: TrackerTransition(s)
        is TrackerEvent.Observe -> observe(s, e)
    }

    private fun observe(prev: TrackerState, e: TrackerEvent.Observe): TrackerTransition {
        val t = e.at
        // Contador de estabilidade da tela.
        val sameAsPending = prev.pendingKind == e.kind
        val s = prev.copy(
            pendingKind = e.kind,
            pendingCount = if (sameAsPending) prev.pendingCount + 1 else 1,
            pendingSince = if (sameAsPending) prev.pendingSince else t,
        )
        val stable = s.pendingCount >= config.stableFrames
        val tl = s.timeline

        // Segurança: corrida aberta tempo demais.
        if (tl != null && t - tl.acceptedAt > config.maxTripMs) {
            return TrackerTransition(TrackerState(), listOf(TrackerEffect.PhaseChanged(TripPhase.NONE, null)))
        }

        return when (s.phase) {
            TripPhase.NONE -> when {
                e.kind == ScreenKind.OFFER && e.offer?.fingerprint != null ->
                    TrackerTransition(
                        s.copy(phase = TripPhase.OFFER, offer = e.offer, offerShownAt = t, offerLastSeenAt = t),
                        listOf(TrackerEffect.PhaseChanged(TripPhase.OFFER, null)),
                    )
                else -> TrackerTransition(s)
            }

            TripPhase.OFFER -> {
                val offer = s.offer ?: return TrackerTransition(TrackerState())
                when (e.kind) {
                    ScreenKind.OFFER -> {
                        val other = e.offer
                        if (other?.fingerprint != null && other.fingerprint != offer.fingerprint) {
                            // Outra oferta substituiu a anterior sem aceite.
                            val outcome = outcomeOnDisappear(s)
                            TrackerTransition(
                                s.copy(offer = other, offerShownAt = t, offerLastSeenAt = t),
                                listOf(TrackerEffect.OutcomeDecided(offer, outcome, OutcomeSource.DETECTED, t)),
                            )
                        } else {
                            TrackerTransition(s.copy(offerLastSeenAt = t, offer = other?.takeIf { it.fingerprint == offer.fingerprint } ?: offer))
                        }
                    }
                    ScreenKind.GOING_TO_PICKUP, ScreenKind.WAITING_PASSENGER, ScreenKind.ON_TRIP ->
                        if (stable) accept(s, s.pendingSince, OutcomeSource.DETECTED, phaseFor(e.kind)) else TrackerTransition(s)
                    ScreenKind.ONLINE_IDLE, ScreenKind.OFFLINE ->
                        if (stable) {
                            TrackerTransition(
                                TrackerState(),
                                listOf(
                                    TrackerEffect.OutcomeDecided(offer, outcomeOnDisappear(s), OutcomeSource.DETECTED, t),
                                    TrackerEffect.PhaseChanged(TripPhase.NONE, null),
                                ),
                            )
                        } else TrackerTransition(s)
                    else ->
                        if (t - s.offerLastSeenAt > config.unknownAfterMs) {
                            TrackerTransition(
                                TrackerState(),
                                listOf(
                                    TrackerEffect.OutcomeDecided(offer, OfferOutcome.UNKNOWN, OutcomeSource.DETECTED, t),
                                    TrackerEffect.PhaseChanged(TripPhase.NONE, null),
                                ),
                            )
                        } else TrackerTransition(s)
                }
            }

            TripPhase.TO_PICKUP, TripPhase.WAITING -> {
                tl ?: return TrackerTransition(TrackerState())
                when (e.kind) {
                    ScreenKind.WAITING_PASSENGER ->
                        if (stable && s.phase == TripPhase.TO_PICKUP) moveTo(s, TripPhase.WAITING, tl.copy(arrivedAt = s.pendingSince))
                        else TrackerTransition(s)
                    ScreenKind.ON_TRIP ->
                        if (stable) moveTo(s, TripPhase.ON_TRIP, tl.copy(startedAt = s.pendingSince, arrivedAt = tl.arrivedAt ?: s.pendingSince))
                        else TrackerTransition(s)
                    ScreenKind.TRIP_COMPLETED, ScreenKind.ONLINE_IDLE, ScreenKind.OFFLINE ->
                        // Voltou a procurar viagens sem iniciar: corrida cancelada.
                        if (s.pendingCount >= config.stableFrames + 1) cancel(tl) else TrackerTransition(s)
                    else -> TrackerTransition(s)
                }
            }

            TripPhase.ON_TRIP -> {
                tl ?: return TrackerTransition(TrackerState())
                when (e.kind) {
                    ScreenKind.TRIP_COMPLETED -> finish(tl, s.pendingSince)
                    ScreenKind.ONLINE_IDLE, ScreenKind.OFFLINE -> if (stable) finish(tl, s.pendingSince) else TrackerTransition(s)
                    // Ofertas durante a viagem (corrida em sequência) não encerram a corrida atual.
                    else -> TrackerTransition(s)
                }
            }
        }
    }

    private fun outcomeOnDisappear(s: TrackerState): OfferOutcome =
        if (s.offerLastSeenAt - s.offerShownAt >= config.expireAfterMs) OfferOutcome.EXPIRED else OfferOutcome.REJECTED

    private fun phaseFor(kind: ScreenKind) = when (kind) {
        ScreenKind.WAITING_PASSENGER -> TripPhase.WAITING
        ScreenKind.ON_TRIP -> TripPhase.ON_TRIP
        else -> TripPhase.TO_PICKUP
    }

    private fun accept(s: TrackerState, at: Long, source: OutcomeSource, phase: TripPhase): TrackerTransition {
        val offer = s.offer ?: return TrackerTransition(s)
        if (s.timeline != null) return TrackerTransition(s)
        val tl = TripTimeline(
            offer = offer,
            acceptedAt = at,
            arrivedAt = if (phase == TripPhase.WAITING || phase == TripPhase.ON_TRIP) at else null,
            startedAt = if (phase == TripPhase.ON_TRIP) at else null,
            acceptSource = source,
        )
        return TrackerTransition(
            s.copy(phase = phase, timeline = tl),
            listOf(
                TrackerEffect.OutcomeDecided(offer, OfferOutcome.ACCEPTED, source, at),
                TrackerEffect.PhaseChanged(phase, tl),
            ),
        )
    }

    private fun moveTo(s: TrackerState, phase: TripPhase, tl: TripTimeline) =
        TrackerTransition(s.copy(phase = phase, timeline = tl), listOf(TrackerEffect.PhaseChanged(phase, tl)))

    private fun finish(tl: TripTimeline, at: Long): TrackerTransition {
        val started = tl.startedAt ?: tl.arrivedAt ?: tl.acceptedAt
        val done = tl.copy(startedAt = started, arrivedAt = tl.arrivedAt ?: started, completedAt = at.coerceAtLeast(started))
        return TrackerTransition(
            TrackerState(),
            listOf(TrackerEffect.TripFinished(done), TrackerEffect.PhaseChanged(TripPhase.NONE, null)),
        )
    }

    private fun cancel(tl: TripTimeline) = TrackerTransition(
        TrackerState(),
        listOf(TrackerEffect.TripCancelled(tl), TrackerEffect.PhaseChanged(TripPhase.NONE, null)),
    )
}
