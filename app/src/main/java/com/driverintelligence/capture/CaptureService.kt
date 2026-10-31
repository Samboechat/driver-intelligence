package com.driverintelligence.capture

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Rect
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.IntentCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.driverintelligence.MainActivity
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.data.repository.AnalysisContextProvider
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.SessionRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.domain.detection.DetectionEffect
import com.driverintelligence.domain.detection.DetectionEvent
import com.driverintelligence.domain.detection.DetectionState
import com.driverintelligence.domain.detection.OfferPhase
import com.driverintelligence.domain.detection.OfferStateMachine
import com.driverintelligence.domain.model.AppSettings
import com.driverintelligence.domain.model.OverlayPrefs
import com.driverintelligence.domain.overlay.OverlayLogic
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.FrameAnalysis
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.recognition.OfferAnalyzer
import com.driverintelligence.overlay.OverlayCallbacks
import com.driverintelligence.overlay.OverlayController
import com.driverintelligence.overlay.TodayStrip
import java.time.LocalDate
import java.time.ZoneId
import com.driverintelligence.recognition.ImagePreprocessor
import com.driverintelligence.recognition.OcrEngine
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Provider

/**
 * Serviço em primeiro plano (tipo mediaProjection) que orquestra:
 * captura → máscara do overlay → OCR → extração → validação → cálculo → classificação → overlay → registro.
 *
 * Processamento sequencial em Dispatchers.Default: nunca há mais de um OCR em andamento
 * (backpressure), o intervalo se adapta à atividade e a análise para com a tela apagada.
 */
@AndroidEntryPoint
class CaptureService : LifecycleService() {

    @Inject lateinit var settingsRepository: SettingsRepository
    @Inject lateinit var contextProvider: AnalysisContextProvider
    @Inject lateinit var offerRepository: OfferRepository
    @Inject lateinit var tripRepository: TripRepository
    @Inject lateinit var sessionRepository: SessionRepository
    @Inject lateinit var analyzer: OfferAnalyzer
    @Inject lateinit var controller: AssistantController
    @Inject lateinit var ocrProvider: Provider<OcrEngine>

    private lateinit var windowCtx: Context
    private var engine: ScreenCaptureEngine? = null
    private var overlay: OverlayController? = null
    private var ocr: OcrEngine? = null
    private val preprocessor = ImagePreprocessor()
    private var loopJob: Job? = null
    private var heartbeatJob: Job? = null
    private var todayJob: Job? = null

    private val machine = OfferStateMachine()
    private var detection = DetectionState()
    private val settings = MutableStateFlow(AppSettings())
    private val analysisContext = MutableStateFlow(AnalysisContext())

    @Volatile private var paused = false
    @Volatile private var resetPending = false
    @Volatile private var currentOfferId: Long? = null
    @Volatile private var currentAnalysis: OfferAnalysis? = null
    /** Escopo independente do ciclo de vida, só para gravações curtas no encerramento. */
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var sessionId: Long? = null
    private var blackFrames = 0
    private var lastOfferActivity = 0L

    override fun onCreate() {
        super.onCreate()
        windowCtx = ScreenCaptureEngine.windowContext(this)
        lifecycleScope.launch {
            settingsRepository.settings.collect {
                settings.value = it
                overlay?.applyPrefs(it.overlay)
            }
        }
        lifecycleScope.launch { contextProvider.context.collect { analysisContext.value = it } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_PAUSE -> setPaused(true)
            ACTION_RESUME -> setPaused(false)
            ACTION_STOP -> shutdown()
            else -> if (engine == null && overlay == null) stopSelf()
        }
        // O token de captura não sobrevive à morte do processo: não reiniciar automaticamente.
        return START_NOT_STICKY
    }

    private fun handleStart(intent: Intent) {
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data = IntentCompat.getParcelableExtra(intent, EXTRA_RESULT_DATA, Intent::class.java)
        if (resultCode != Activity.RESULT_OK || data == null) {
            if (engine == null) stopSelf()
            return
        }
        // 1. Primeiro plano ANTES de obter a projeção (exigência do Android 14+).
        try {
            ServiceCompat.startForeground(
                this,
                CaptureNotifications.NOTIFICATION_ID,
                CaptureNotifications.build(this, paused = false),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Não foi possível iniciar o serviço em primeiro plano", e)
            controller.update { it.copy(status = AssistantStatus.STOPPED, message = "O sistema não permitiu iniciar a captura.") }
            stopSelf()
            return
        }

        // Novo token: descarta qualquer captura anterior.
        stopCapture(stopProjection = true)

        val mpm = getSystemService(MediaProjectionManager::class.java)
        val projection = try {
            mpm.getMediaProjection(resultCode, data)
        } catch (e: Exception) {
            Log.e(TAG, "Falha ao obter MediaProjection", e)
            null
        }
        if (projection == null) {
            controller.update { it.copy(status = AssistantStatus.STOPPED, message = "Autorização de captura inválida. Tente novamente.") }
            shutdown()
            return
        }

        if (!Settings.canDrawOverlays(this)) {
            projection.stop()
            controller.update { it.copy(status = AssistantStatus.STOPPED, message = "Permissão de sobreposição necessária.") }
            shutdown()
            return
        }

        // Garante preferências e veículo atuais antes de montar overlay e captura.
        lifecycleScope.launch {
            settings.value = settingsRepository.settings.first()
            analysisContext.value = contextProvider.context.first()
            startCapture(projection)
        }
    }

    private fun startCapture(projection: MediaProjection) {
        val capture = ScreenCaptureEngine(windowCtx, projection, settings.value.capture.maxWidth) {
            lifecycleScope.launch { onProjectionStopped() }
        }
        try {
            capture.start()
        } catch (e: Exception) {
            Log.e(TAG, "Falha ao iniciar a captura", e)
            capture.release(stopProjection = true)
            controller.update { it.copy(status = AssistantStatus.STOPPED, message = "Falha ao iniciar a captura de tela.") }
            shutdown()
            return
        }
        engine = capture
        ocr = ocrProvider.get()
        paused = false
        detection = DetectionState()
        blackFrames = 0

        ensureOverlay()
        overlay?.showWaiting()
        observeToday()
        startSession()
        startLoop()
        controller.update {
            it.copy(status = AssistantStatus.RUNNING, phase = OfferPhase.IDLE, startedAt = System.currentTimeMillis(), message = null)
        }
    }

    // ---------------- Loop de processamento ----------------

    private fun startLoop() {
        loopJob?.cancel()
        loopJob = lifecycleScope.launch(Dispatchers.Default) {
            val power = getSystemService(PowerManager::class.java)
            while (isActive) {
                if (resetPending) {
                    resetPending = false
                    detection = DetectionState(recentlyRecorded = detection.recentlyRecorded)
                }
                val prefs = settings.value.capture
                val idle = SystemClock.elapsedRealtime() - lastOfferActivity > IDLE_AFTER_MS
                val interval = if (idle) prefs.idleIntervalMs else prefs.activeIntervalMs
                val capture = engine
                if (paused || capture == null || !power.isInteractive) {
                    delay(interval)
                    continue
                }
                val started = SystemClock.elapsedRealtime()
                val frame = capture.nextFrame(timeoutMs = interval + 1_000)
                if (frame != null) {
                    try {
                        processFrame(frame)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (oom: OutOfMemoryError) {
                        Log.w(TAG, "Memória insuficiente no processamento", oom)
                        dispatch(DetectionEvent.ProcessingFailed("Memória insuficiente; reduzindo processamento.", System.currentTimeMillis()))
                        delay(2_000)
                    } catch (e: Exception) {
                        Log.w(TAG, "Falha no processamento do frame", e)
                        controller.update { it.copy(ocrFailures = it.ocrFailures + 1) }
                        dispatch(DetectionEvent.ProcessingFailed("Falha ao ler a tela.", System.currentTimeMillis()))
                    }
                }
                val elapsed = SystemClock.elapsedRealtime() - started
                delay((interval - elapsed).coerceAtLeast(MIN_GAP_MS))
            }
        }
    }

    private suspend fun processFrame(frame: CapturedFrame) {
        val bitmap = frame.bitmap
        setPhase(OfferPhase.EXTRACTING)

        // Tela protegida (FLAG_SECURE) ou apagada: frame preto.
        if (ImagePreprocessor.isMostlyBlack(bitmap)) {
            blackFrames++
            if (blackFrames == BLACK_FRAMES_TO_BLOCK) {
                withContext(Dispatchers.Main) {
                    overlay?.showBlocked("A tela atual não pode ser lida (protegida ou escura). Use a inserção manual.")
                }
                controller.update { it.copy(status = AssistantStatus.BLOCKED) }
            }
            dispatch(DetectionEvent.FrameAnalyzed(FrameAnalysis(false, null), System.currentTimeMillis()))
            return
        }
        if (blackFrames >= BLACK_FRAMES_TO_BLOCK) {
            withContext(Dispatchers.Main) { overlay?.showWaiting() }
            controller.update { it.copy(status = AssistantStatus.RUNNING) }
        }
        blackFrames = 0

        val prefs = settings.value.capture
        val mask = overlay?.bounds?.let { r ->
            val padding = (6 * resources.displayMetrics.density).toInt()
            val a = OverlayLogic.scaleRect(r.left, r.top, r.right, r.bottom, frame.scale, padding)
            Rect(a[0], a[1], a[2], a[3])
        }
        val prepared = preprocessor.prepare(bitmap, prefs.region, mask, prefs.enhanceContrast)
        val engineOcr = ocr ?: return
        val t0 = SystemClock.elapsedRealtime()
        val text = engineOcr.recognize(prepared.bitmap)
        controller.recordOcrTime(SystemClock.elapsedRealtime() - t0)
        if (prepared.owned) prepared.bitmap.recycle()

        setPhase(OfferPhase.VALIDATING)
        val result = analyzer.analyzeFrame(text, analysisContext.value)
        setPhase(OfferPhase.CALCULATING)
        dispatch(DetectionEvent.FrameAnalyzed(result, System.currentTimeMillis()))
    }

    private suspend fun dispatch(event: DetectionEvent) {
        val transition = machine.reduce(detection, event)
        detection = transition.state
        setPhase(transition.state.phase)
        if (transition.state.phase != OfferPhase.IDLE) lastOfferActivity = SystemClock.elapsedRealtime()
        for (effect in transition.effects) handleEffect(effect)
    }

    private suspend fun handleEffect(effect: DetectionEffect) {
        val haptics = settings.value.overlay.haptics
        when (effect) {
            is DetectionEffect.ShowOffer -> {
                if (effect.analysis.fingerprint != currentAnalysis?.fingerprint) currentOfferId = null
                currentAnalysis = effect.analysis
                controller.update { it.copy(lastAnalysis = effect.analysis, offersShown = it.offersShown + if (effect.changed || it.lastAnalysis?.fingerprint != effect.analysis.fingerprint) 1 else 0) }
                withContext(Dispatchers.Main) { overlay?.showOffer(effect.analysis, effect.changed, haptics) }
            }
            is DetectionEffect.ShowReading -> withContext(Dispatchers.Main) { overlay?.showReading() }
            DetectionEffect.ClearOffer -> {
                currentAnalysis = null
                currentOfferId = null
                withContext(Dispatchers.Main) { overlay?.clearOffer() }
            }
            is DetectionEffect.RecordAnalyzedOffer -> {
                val analysis = effect.analysis
                lifecycleScope.launch(Dispatchers.IO) {
                    val id = offerRepository.record(analysis, analysisContext.value.vehicleId)
                    if (currentAnalysis?.fingerprint == analysis.fingerprint) currentOfferId = id
                }
            }
            is DetectionEffect.ShowError -> withContext(Dispatchers.Main) { overlay?.showError(effect.message) }
        }
    }

    private fun setPhase(phase: OfferPhase) {
        if (controller.state.value.phase != phase) controller.update { it.copy(phase = phase) }
    }

    // ---------------- Overlay ----------------

    private fun ensureOverlay() {
        if (overlay != null) return
        overlay = OverlayController(windowCtx, settings.value.overlay, overlayCallbacks).also {
            try {
                it.show()
            } catch (e: Exception) {
                Log.e(TAG, "Não foi possível exibir o overlay", e)
            }
        }
    }

    private val overlayCallbacks = object : OverlayCallbacks {
        override fun onPauseToggle() = setPaused(!paused)

        override fun onClose() = shutdown()

        override fun onRegisterTrip() {
            val analysis = currentAnalysis ?: return
            lifecycleScope.launch(Dispatchers.IO) {
                val offerId = currentOfferId ?: offerRepository.record(analysis, analysisContext.value.vehicleId)
                val offer = offerId?.let { offerRepository.get(it) } ?: return@launch
                tripRepository.registerFromOffer(offer)
                withContext(Dispatchers.Main) { overlay?.markRegistered() }
            }
        }

        override fun onManualInput() {
            val o = currentAnalysis?.offer
            val intent = Intent(this@CaptureService, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_ROUTE, MainActivity.ROUTE_MANUAL)
            o?.fare?.let { intent.putExtra(MainActivity.EXTRA_FARE, it) }
            o?.pickupDistanceKm?.let { intent.putExtra(MainActivity.EXTRA_PICKUP_KM, it) }
            o?.tripDistanceKm?.let { intent.putExtra(MainActivity.EXTRA_TRIP_KM, it) }
            o?.pickupTimeMin?.let { intent.putExtra(MainActivity.EXTRA_PICKUP_MIN, it) }
            o?.tripTimeMin?.let { intent.putExtra(MainActivity.EXTRA_TRIP_MIN, it) }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Não foi possível abrir a inserção manual", e)
            }
        }

        override fun onRestartCapture() = controller.requestStart(this@CaptureService)

        override fun onPrefsChanged(transform: (OverlayPrefs) -> OverlayPrefs) {
            lifecycleScope.launch { settingsRepository.updateOverlay(transform) }
        }
    }

    private fun setPaused(value: Boolean) {
        if (engine == null) return
        paused = value
        if (value) {
            currentAnalysis = null
            currentOfferId = null
            resetPending = true
        }
        overlay?.showPaused(value)
        controller.update { it.copy(status = if (value) AssistantStatus.PAUSED else AssistantStatus.RUNNING) }
        updateNotification()
    }

    private fun updateNotification() {
        if (engine == null) return
        val nm = getSystemService(android.app.NotificationManager::class.java)
        try {
            nm.notify(CaptureNotifications.NOTIFICATION_ID, CaptureNotifications.build(this, paused))
        } catch (_: SecurityException) {
            // Notificações negadas pelo usuário: o serviço continua funcionando.
        }
    }

    // ---------------- Ciclo de vida ----------------

    /** Autorização revogada pelo usuário, tela bloqueada (Android 15+) ou outro app iniciou captura. */
    private fun onProjectionStopped() {
        if (engine == null) return
        stopCapture(stopProjection = false)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        overlay?.showCaptureStopped("A autorização de captura foi encerrada. Toque em retomar para continuar.")
        controller.update { it.copy(status = AssistantStatus.CAPTURE_INTERRUPTED, phase = OfferPhase.IDLE) }
    }

    private fun stopCapture(stopProjection: Boolean) {
        loopJob?.cancel()
        loopJob = null
        heartbeatJob?.cancel()
        heartbeatJob = null
        todayJob?.cancel()
        todayJob = null
        engine?.release(stopProjection)
        engine = null
        ocr?.close()
        ocr = null
        preprocessor.release()
        detection = DetectionState()
        currentAnalysis = null
        currentOfferId = null
        closeSession()
    }

    private fun shutdown() {
        stopCapture(stopProjection = true)
        overlay?.remove()
        overlay = null
        controller.update { it.copy(status = AssistantStatus.STOPPED, phase = OfferPhase.IDLE, lastAnalysis = null) }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Faturamento do dia (corridas registradas) para o rodapé do overlay. */
    private fun observeToday() {
        todayJob?.cancel()
        val zone = ZoneId.systemDefault()
        val start = LocalDate.now(zone).atStartOfDay(zone).toInstant().toEpochMilli()
        val end = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        todayJob = lifecycleScope.launch {
            combine(tripRepository.tripsBetween(start, end), settingsRepository.settings) { trips, s ->
                if (!s.overlay.showDailyProgress) {
                    null
                } else {
                    val profits = trips.mapNotNull { it.estimatedProfit }
                    TodayStrip(
                        revenue = trips.sumOf { it.fare },
                        goal = s.goals.dailyRevenue,
                        trips = trips.size,
                        profit = if (profits.isEmpty()) null else profits.sum(),
                    )
                }
            }.collect { overlay?.updateToday(it) }
        }
    }

    private fun startSession() {
        val now = System.currentTimeMillis()
        heartbeatJob?.cancel()
        heartbeatJob = lifecycleScope.launch(Dispatchers.IO) {
            val id = sessionRepository.start(now)
            sessionId = id
            while (isActive) {
                delay(HEARTBEAT_MS)
                sessionRepository.heartbeat(id, System.currentTimeMillis())
            }
        }
    }

    private fun closeSession() {
        val id = sessionId ?: return
        sessionId = null
        val end = System.currentTimeMillis()
        // O escopo do serviço pode estar encerrando: grava o fim da sessão num escopo independente.
        ioScope.launch { sessionRepository.heartbeat(id, end) }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        engine?.onDisplayChanged()
        overlay?.onScreenChanged()
    }

    override fun onDestroy() {
        stopCapture(stopProjection = true)
        overlay?.remove()
        overlay = null
        controller.update { it.copy(status = AssistantStatus.STOPPED, phase = OfferPhase.IDLE) }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "CaptureService"
        const val ACTION_START = "com.driverintelligence.action.START"
        const val ACTION_PAUSE = "com.driverintelligence.action.PAUSE"
        const val ACTION_RESUME = "com.driverintelligence.action.RESUME"
        const val ACTION_STOP = "com.driverintelligence.action.STOP"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private const val IDLE_AFTER_MS = 10_000L
        private const val MIN_GAP_MS = 60L
        private const val HEARTBEAT_MS = 60_000L
        private const val BLACK_FRAMES_TO_BLOCK = 3
    }
}
