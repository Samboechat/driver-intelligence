package com.driverintelligence.capture

import android.content.Context
import android.content.Intent
import com.driverintelligence.domain.detection.OfferPhase
import com.driverintelligence.domain.recognition.OfferAnalysis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

enum class AssistantStatus(val label: String) {
    STOPPED("Desligado"),
    RUNNING("Ativo"),
    PAUSED("Pausado"),
    CAPTURE_INTERRUPTED("Captura interrompida"),
    BLOCKED("Leitura bloqueada pelo app"),
}

/** Estado observável do assistente + métricas locais de desempenho e falhas (sem envio externo). */
data class AssistantState(
    val status: AssistantStatus = AssistantStatus.STOPPED,
    val phase: OfferPhase = OfferPhase.IDLE,
    val lastAnalysis: OfferAnalysis? = null,
    val startedAt: Long? = null,
    val framesAnalyzed: Long = 0,
    val offersShown: Int = 0,
    val ocrFailures: Int = 0,
    val lastOcrMs: Long? = null,
    val avgOcrMs: Double? = null,
    val message: String? = null,
)

@Singleton
class AssistantController @Inject constructor() {
    private val _state = MutableStateFlow(AssistantState())
    val state: StateFlow<AssistantState> = _state.asStateFlow()

    fun update(transform: (AssistantState) -> AssistantState) = _state.update(transform)

    fun recordOcrTime(ms: Long) = _state.update { s ->
        val n = s.framesAnalyzed + 1
        val avg = s.avgOcrMs?.let { it + (ms - it) / n.coerceAtMost(50) } ?: ms.toDouble()
        s.copy(framesAnalyzed = n, lastOcrMs = ms, avgOcrMs = avg)
    }

    /** Abre o pedido de consentimento de captura e, se autorizado, inicia o serviço. */
    fun requestStart(context: Context) {
        context.startActivity(
            Intent(context, CaptureConsentActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun stop(context: Context) = send(context, CaptureService.ACTION_STOP)
    fun pause(context: Context) = send(context, CaptureService.ACTION_PAUSE)
    fun resume(context: Context) = send(context, CaptureService.ACTION_RESUME)

    private fun send(context: Context, action: String) {
        if (_state.value.status == AssistantStatus.STOPPED) return
        context.startService(Intent(context, CaptureService::class.java).setAction(action))
    }
}
