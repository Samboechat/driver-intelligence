package com.driverintelligence.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowManager
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import com.driverintelligence.capture.ScreenCaptureEngine
import com.driverintelligence.designsystem.DriverIntelligenceTheme
import com.driverintelligence.domain.detection.TripPhase
import com.driverintelligence.domain.detection.TripTimeline
import com.driverintelligence.domain.model.OverlayPrefs
import com.driverintelligence.domain.model.ThemeMode
import com.driverintelligence.domain.overlay.OverlayAction
import com.driverintelligence.domain.overlay.OverlayLogic
import com.driverintelligence.domain.overlay.OverlayMode
import com.driverintelligence.domain.recognition.OfferAnalysis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

enum class OverlayKind { WAITING, READING, OFFER, TRIP, SUMMARY, PAUSED, CAPTURE_STOPPED, BLOCKED, ERROR }

/** Corrida aceita em andamento (o cartão atualiza a cada segundo). */
data class LiveTrip(
    val phase: TripPhase,
    val timeline: TripTimeline,
    /** Previsão de busca e viagem em minutos (tempo realista quando disponível). */
    val predictedPickupMin: Double?,
    val predictedTripMin: Double?,
    /** Tempo exibido pelo app na oferta. */
    val offeredPickupMin: Double?,
    val offeredTripMin: Double?,
    val fare: Double?,
    val estimatedCost: Double?,
    val goalPerHour: Double,
)

/** Resumo exibido ao fim de uma corrida acompanhada. */
data class TripSummary(
    val timeline: TripTimeline,
    val predictedTotalMin: Double?,
    val offeredTotalMin: Double?,
    val revenuePerHour: Double?,
    val profit: Double?,
    val registered: Boolean,
    val cancelled: Boolean = false,
)

/** Resumo do dia exibido no rodapé do overlay. */
data class TodayStrip(val revenue: Double, val goal: Double?, val trips: Int, val profit: Double?)

data class OverlayUiState(
    val mode: OverlayMode = OverlayMode.COMPACT,
    val opacity: Float = 0.94f,
    val textScale: Float = 1f,
    val today: TodayStrip? = null,
    val kind: OverlayKind = OverlayKind.WAITING,
    val analysis: OfferAnalysis? = null,
    val message: String? = null,
    /** Incrementado a cada oferta nova — dispara o feedback visual. */
    val pulse: Int = 0,
    /** O motorista marcou a oferta exibida como aceita. */
    val offerAccepted: Boolean = false,
    val trip: LiveTrip? = null,
    val summary: TripSummary? = null,
)

interface OverlayCallbacks {
    fun onPauseToggle()
    fun onClose()
    fun onAccept()
    fun onReject()
    fun onFinishTrip()
    fun onCancelTrip()
    fun onDismissSummary()
    fun onManualInput()
    fun onRestartCapture()
    fun onPrefsChanged(transform: (OverlayPrefs) -> OverlayPrefs)
}

/**
 * Janela flutuante (TYPE_APPLICATION_OVERLAY) com conteúdo em Compose.
 *
 * - Não é focável (FLAG_NOT_FOCUSABLE) e não é modal: toques fora dela vão para o app de baixo.
 * - Nunca toca, clica ou altera o Uber Driver — apenas exibe informação.
 * - Posição salva como fração da tela, para sobreviver a rotação e mudanças de resolução.
 * - Expõe o retângulo atual ([bounds]) para o pipeline mascará-lo antes do OCR.
 *
 * Todas as chamadas públicas devem ocorrer na thread principal, exceto [bounds].
 */
class OverlayController(
    /** Contexto de janela (ver ScreenCaptureEngine.windowContext). */
    private val windowContext: Context,
    initial: OverlayPrefs,
    private val callbacks: OverlayCallbacks,
) {
    private val wm = windowContext.getSystemService(WindowManager::class.java)
    private val owner = OverlayLifecycleOwner()
    private val _state = MutableStateFlow(OverlayUiState(mode = initial.mode, opacity = initial.opacity, textScale = initial.textScale))
    val state: StateFlow<OverlayUiState> = _state.asStateFlow()

    private var prefs = initial
    private var view: ComposeView? = null
    private var positioned = false

    @Volatile var bounds: Rect? = null
        private set

    private val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        title = "DriverIntelligenceOverlay"
    }

    val isShowing: Boolean get() = view != null

    fun show() {
        if (view != null) return
        owner.create()
        val v = ComposeView(windowContext).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindowOrReleasedFromPool)
        }
        owner.attach(v)
        v.setContent {
            DriverIntelligenceTheme(mode = ThemeMode.DARK) {
                OverlayContent(
                    stateFlow = state,
                    onDrag = ::dragBy,
                    onDragEnd = ::persistPosition,
                    onAction = ::onModeAction,
                    onOpacityStep = ::stepOpacity,
                    callbacks = callbacks,
                )
            }
        }
        v.addOnLayoutChangeListener { changed, _, _, _, _, _, _, _, _ ->
            if (!positioned && changed.width > 0) {
                positioned = true
                applyRelativePosition()
            } else {
                clampAndUpdate()
            }
            updateBounds()
        }
        owner.resume()
        // Posição aproximada antes da primeira medição (evita "pulo" a partir do canto).
        val density = windowContext.resources.displayMetrics.density
        val (sw, sh) = ScreenCaptureEngine.screenSize(windowContext)
        val (x, y) = OverlayLogic.fromRelative(prefs.relX, prefs.relY, (240 * density).toInt(), (160 * density).toInt(), sw, sh)
        params.x = x
        params.y = y
        wm.addView(v, params)
        view = v
    }

    fun remove() {
        val v = view ?: return
        view = null
        bounds = null
        try {
            wm.removeViewImmediate(v)
        } catch (_: Throwable) {}
        owner.destroy()
    }

    // ---- Conteúdo ----

    fun showWaiting() = _state.update {
        it.copy(kind = if (it.trip != null) OverlayKind.TRIP else OverlayKind.WAITING, analysis = null, message = null, offerAccepted = false)
    }

    fun showReading() = _state.update {
        if (it.kind == OverlayKind.OFFER) it else it.copy(kind = OverlayKind.READING, message = null)
    }

    fun showOffer(analysis: OfferAnalysis, changed: Boolean, haptics: Boolean) {
        val isNew = _state.value.analysis?.fingerprint != analysis.fingerprint
        _state.update {
            it.copy(
                kind = OverlayKind.OFFER,
                analysis = analysis,
                message = null,
                pulse = if (isNew || changed) it.pulse + 1 else it.pulse,
                offerAccepted = if (isNew) false else it.offerAccepted,
            )
        }
        if (isNew && haptics) {
            view?.performHapticFeedback(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY,
            )
        }
    }

    /** A oferta sumiu: volta para a corrida em andamento, o resumo ou a espera. */
    fun clearOffer() = _state.update {
        it.copy(
            analysis = null,
            message = null,
            offerAccepted = false,
            kind = when {
                it.trip != null -> OverlayKind.TRIP
                it.summary != null -> OverlayKind.SUMMARY
                else -> OverlayKind.WAITING
            },
        )
    }

    fun showTrip(trip: LiveTrip) = _state.update {
        val offerOnScreen = it.kind == OverlayKind.OFFER && it.analysis != null && it.analysis.fingerprint != trip.timeline.offer.fingerprint
        it.copy(trip = trip, summary = null, kind = if (offerOnScreen) OverlayKind.OFFER else OverlayKind.TRIP)
    }

    fun endTrip(summary: TripSummary?) = _state.update {
        val offerOnScreen = it.kind == OverlayKind.OFFER && it.analysis != null && it.analysis.fingerprint != summary?.timeline?.offer?.fingerprint
        it.copy(
            trip = null,
            summary = summary,
            kind = when {
                offerOnScreen -> OverlayKind.OFFER
                summary != null -> OverlayKind.SUMMARY
                else -> OverlayKind.WAITING
            },
        )
    }

    fun dismissSummary() = _state.update {
        if (it.kind == OverlayKind.SUMMARY) {
            it.copy(summary = null, kind = if (it.trip != null) OverlayKind.TRIP else OverlayKind.WAITING)
        } else it.copy(summary = null)
    }

    fun showPaused(paused: Boolean) = _state.update {
        if (paused) it.copy(kind = OverlayKind.PAUSED, analysis = null, message = null) else it.copy(kind = OverlayKind.WAITING, message = null)
    }

    fun showCaptureStopped(message: String) = _state.update { it.copy(kind = OverlayKind.CAPTURE_STOPPED, analysis = null, message = message) }

    fun showBlocked(message: String) = _state.update { it.copy(kind = OverlayKind.BLOCKED, analysis = null, message = message) }

    fun showError(message: String) = _state.update {
        if (it.kind == OverlayKind.OFFER) it else it.copy(kind = OverlayKind.ERROR, message = message)
    }

    fun markAccepted() = _state.update { it.copy(offerAccepted = true) }

    fun updateToday(today: TodayStrip?) = _state.update { it.copy(today = today) }

    /** Aplica mudanças feitas nos Ajustes enquanto o assistente está ativo. */
    fun applyPrefs(p: OverlayPrefs) {
        prefs = prefs.copy(opacity = p.opacity, textScale = p.textScale, haptics = p.haptics, showDailyProgress = p.showDailyProgress)
        _state.update { it.copy(opacity = p.opacity, textScale = p.textScale) }
    }

    // ---- Janela ----

    private fun onModeAction(action: OverlayAction) {
        val next = OverlayLogic.nextMode(_state.value.mode, action)
        _state.update { it.copy(mode = next) }
        prefs = prefs.copy(mode = next)
        callbacks.onPrefsChanged { it.copy(mode = next) }
    }

    private fun stepOpacity(delta: Float) {
        val next = (_state.value.opacity + delta).coerceIn(0.5f, 1f)
        _state.update { it.copy(opacity = next) }
        prefs = prefs.copy(opacity = next)
        callbacks.onPrefsChanged { it.copy(opacity = next) }
    }

    private fun dragBy(dx: Float, dy: Float) {
        val v = view ?: return
        params.x += dx.toInt()
        params.y += dy.toInt()
        clampInto(v)
        try {
            wm.updateViewLayout(v, params)
        } catch (_: Throwable) {}
        updateBounds()
    }

    private fun persistPosition() {
        val v = view ?: return
        val (sw, sh) = ScreenCaptureEngine.screenSize(windowContext)
        val (rx, ry) = OverlayLogic.toRelative(params.x, params.y, v.width, v.height, sw, sh)
        prefs = prefs.copy(relX = rx, relY = ry)
        callbacks.onPrefsChanged { it.copy(relX = rx, relY = ry) }
    }

    private fun applyRelativePosition() {
        val v = view ?: return
        val (sw, sh) = ScreenCaptureEngine.screenSize(windowContext)
        val (x, y) = OverlayLogic.fromRelative(prefs.relX, prefs.relY, v.width, v.height, sw, sh)
        params.x = x
        params.y = y
        clampInto(v)
        try {
            wm.updateViewLayout(v, params)
        } catch (_: Throwable) {}
    }

    /** Chamado após rotação/mudança de resolução: reposiciona pela fração salva. */
    fun onScreenChanged() {
        if (view == null) return
        applyRelativePosition()
        updateBounds()
    }

    private fun clampAndUpdate() {
        val v = view ?: return
        val oldX = params.x
        val oldY = params.y
        clampInto(v)
        if (oldX != params.x || oldY != params.y) {
            try {
                wm.updateViewLayout(v, params)
            } catch (_: Throwable) {}
        }
    }

    private fun clampInto(v: View) {
        val (sw, sh) = ScreenCaptureEngine.screenSize(windowContext)
        val margin = (8 * v.resources.displayMetrics.density).toInt()
        val (x, y) = OverlayLogic.clamp(params.x, params.y, v.width, v.height, sw, sh, margin)
        params.x = x
        params.y = y
    }

    private fun updateBounds() {
        val v = view ?: return
        if (!v.isAttachedToWindow || v.width == 0) return
        val loc = IntArray(2)
        v.getLocationOnScreen(loc)
        bounds = Rect(loc[0], loc[1], loc[0] + v.width, loc[1] + v.height)
    }
}
