package com.driverintelligence.domain.detection

import com.driverintelligence.domain.recognition.FrameAnalysis
import com.driverintelligence.domain.recognition.OfferAnalysis

/**
 * Fases do ciclo de vida de uma oferta.
 * EXTRACTING, VALIDATING e CALCULATING são fases transitórias do pipeline de um frame
 * (publicadas pelo processador para diagnóstico); as demais são mantidas por esta máquina.
 */
enum class OfferPhase {
    IDLE,
    SCREEN_DETECTED,
    OFFER_DETECTED,
    EXTRACTING,
    VALIDATING,
    CALCULATING,
    DISPLAYING,
    OFFER_CHANGED,
    OFFER_DISMISSED,
    ERROR,
}

data class DetectionConfig(
    /** Frames consecutivos com a mesma oferta para confirmar leituras de confiança média. */
    val confirmFrames: Int = 2,
    /** Confiança a partir da qual a oferta é exibida já no primeiro frame. */
    val instantConfidence: Double = 0.85,
    /** Frames consecutivos sem oferta para considerá-la encerrada. */
    val dismissAfterMissingFrames: Int = 2,
    /** Janela em que a mesma oferta não é registrada de novo no histórico. */
    val dedupWindowMs: Long = 120_000,
    /** Melhoria mínima de confiança para atualizar uma oferta já exibida. */
    val confidenceUpdateDelta: Double = 0.10,
)

data class DetectionState(
    val phase: OfferPhase = OfferPhase.IDLE,
    val current: OfferAnalysis? = null,
    val candidateFingerprint: String? = null,
    val candidateHits: Int = 0,
    val missingFrames: Int = 0,
    val recentlyRecorded: Map<String, Long> = emptyMap(),
    val errorMessage: String? = null,
)

sealed interface DetectionEvent {
    data class FrameAnalyzed(val frame: FrameAnalysis, val timestampMs: Long) : DetectionEvent
    data class ProcessingFailed(val message: String, val timestampMs: Long) : DetectionEvent
    data object Reset : DetectionEvent
}

sealed interface DetectionEffect {
    /** Exibir/atualizar a análise no overlay. */
    data class ShowOffer(val analysis: OfferAnalysis, val changed: Boolean) : DetectionEffect
    /** Tela de oferta detectada, leitura ainda insuficiente. */
    data class ShowReading(val partial: OfferAnalysis?) : DetectionEffect
    data object ClearOffer : DetectionEffect
    /** Registrar como OFERTA ANALISADA (nunca como corrida realizada). */
    data class RecordAnalyzedOffer(val analysis: OfferAnalysis) : DetectionEffect
    data class ShowError(val message: String) : DetectionEffect
}

data class Transition(val state: DetectionState, val effects: List<DetectionEffect> = emptyList())

/** Máquina de estados pura e determinística: (estado, evento) → (novo estado, efeitos). */
class OfferStateMachine(private val config: DetectionConfig = DetectionConfig()) {

    fun reduce(state: DetectionState, event: DetectionEvent): Transition = when (event) {
        DetectionEvent.Reset -> Transition(
            DetectionState(recentlyRecorded = state.recentlyRecorded),
            if (state.current != null || state.phase == OfferPhase.SCREEN_DETECTED) listOf(DetectionEffect.ClearOffer) else emptyList(),
        )
        is DetectionEvent.ProcessingFailed -> {
            val effects = if (state.phase != OfferPhase.ERROR) listOf(DetectionEffect.ShowError(event.message)) else emptyList()
            Transition(state.copy(phase = OfferPhase.ERROR, errorMessage = event.message), effects)
        }
        is DetectionEvent.FrameAnalyzed -> onFrame(state, event)
    }

    private fun onFrame(previous: DetectionState, event: DetectionEvent.FrameAnalyzed): Transition {
        val now = event.timestampMs
        val state = previous.copy(
            recentlyRecorded = previous.recentlyRecorded.filterValues { now - it <= config.dedupWindowMs },
            errorMessage = null,
        )
        val analysis = event.frame.analysis
        val fingerprint = analysis?.fingerprint

        // Tela de oferta presente, mas leitura sem os dados essenciais.
        if (event.frame.isOfferScreen && (analysis == null || fingerprint == null)) {
            return when {
                // Mantém a oferta exibida: leitura parcial não significa que ela sumiu.
                state.current != null -> Transition(state.copy(missingFrames = 0))
                state.phase == OfferPhase.SCREEN_DETECTED || state.phase == OfferPhase.OFFER_DETECTED ->
                    Transition(state.copy(phase = OfferPhase.SCREEN_DETECTED, missingFrames = 0))
                else -> Transition(
                    state.copy(phase = OfferPhase.SCREEN_DETECTED, missingFrames = 0, candidateFingerprint = null, candidateHits = 0),
                    listOf(DetectionEffect.ShowReading(analysis)),
                )
            }
        }

        // Nenhuma oferta na tela.
        if (!event.frame.isOfferScreen || analysis == null || fingerprint == null) {
            val active = state.current != null || state.phase == OfferPhase.SCREEN_DETECTED ||
                state.phase == OfferPhase.OFFER_DETECTED
            if (!active) return Transition(state.copy(phase = OfferPhase.IDLE, missingFrames = 0))
            val missing = state.missingFrames + 1
            if (missing >= config.dismissAfterMissingFrames) {
                return Transition(
                    state.copy(
                        phase = if (state.current != null) OfferPhase.OFFER_DISMISSED else OfferPhase.IDLE,
                        current = null,
                        candidateFingerprint = null,
                        candidateHits = 0,
                        missingFrames = 0,
                    ),
                    listOf(DetectionEffect.ClearOffer),
                )
            }
            return Transition(state.copy(missingFrames = missing))
        }

        // Mesma oferta já exibida: evita atualização excessiva do overlay.
        val current = state.current
        if (current != null && current.fingerprint == fingerprint) {
            val better = analysis.confidence >= current.confidence + config.confidenceUpdateDelta
            return if (better) {
                Transition(
                    state.copy(phase = OfferPhase.DISPLAYING, current = analysis, missingFrames = 0),
                    listOf(DetectionEffect.ShowOffer(analysis, changed = false)),
                )
            } else {
                Transition(state.copy(phase = OfferPhase.DISPLAYING, missingFrames = 0))
            }
        }

        // Oferta nova (ou diferente da exibida).
        val hits = if (state.candidateFingerprint == fingerprint) state.candidateHits + 1 else 1
        val confirmed = analysis.confidence >= config.instantConfidence || hits >= config.confirmFrames
        if (!confirmed) {
            val effects = if (state.candidateFingerprint != fingerprint && current == null) {
                listOf(DetectionEffect.ShowReading(analysis))
            } else emptyList()
            return Transition(
                state.copy(
                    phase = OfferPhase.OFFER_DETECTED,
                    candidateFingerprint = fingerprint,
                    candidateHits = hits,
                    missingFrames = 0,
                ),
                effects,
            )
        }

        val changed = current != null
        val effects = mutableListOf<DetectionEffect>(DetectionEffect.ShowOffer(analysis, changed))
        var recorded = state.recentlyRecorded
        if (fingerprint !in recorded) {
            effects += DetectionEffect.RecordAnalyzedOffer(analysis)
            recorded = recorded + (fingerprint to now)
        }
        return Transition(
            state.copy(
                phase = if (changed) OfferPhase.OFFER_CHANGED else OfferPhase.DISPLAYING,
                current = analysis,
                candidateFingerprint = null,
                candidateHits = 0,
                missingFrames = 0,
                recentlyRecorded = recorded,
            ),
            effects,
        )
    }
}
