package com.driverintelligence.capture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.WindowManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.roundToInt

/** Frame capturado, já convertido em bitmap reduzido. [scale] = largura do frame ÷ largura da tela. */
class CapturedFrame(val bitmap: Bitmap, val scale: Float, val screenWidth: Int, val screenHeight: Int)

/**
 * Captura de tela autorizada via MediaProjection.
 *
 * - Callback registrado ANTES de createVirtualDisplay (obrigatório no Android 14+).
 * - Um único VirtualDisplay por token (Android 14+ não permite recriar); rotação usa resize().
 * - Frames são puxados sob demanda: o leitor descarta imagens enquanto ninguém pede,
 *   e só converte para bitmap quando o processador solicita (backpressure natural).
 * - O bitmap de saída é reutilizado entre frames.
 */
class ScreenCaptureEngine(
    /** Contexto de janela (ver [windowContext]) — criado uma única vez pelo serviço. */
    private val context: Context,
    private val projection: MediaProjection,
    private val maxWidth: Int,
    private val onProjectionStopped: () -> Unit,
) {
    private val thread = HandlerThread("di-capture").apply { start() }
    private val handler = Handler(thread.looper)

    private var reader: ImageReader? = null
    private var display: VirtualDisplay? = null
    private var reusable: Bitmap? = null

    @Volatile private var pending: CompletableDeferred<CapturedFrame?>? = null
    @Volatile private var released = false

    var frameWidth = 0
        private set
    var frameHeight = 0
        private set
    private var screenWidth = 0
    private var screenHeight = 0
    private var scale = 1f

    private val callback = object : MediaProjection.Callback() {
        override fun onStop() {
            if (!released) onProjectionStopped()
        }
    }

    fun start() {
        projection.registerCallback(callback, handler)
        val size = computeSize()
        apply(size)
        val r = newReader(size.w, size.h)
        reader = r
        display = projection.createVirtualDisplay(
            "DriverIntelligence",
            size.w,
            size.h,
            size.dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            r.surface,
            null,
            handler,
        )
    }

    /** Ajusta o tamanho após rotação ou mudança de resolução, mantendo o mesmo VirtualDisplay. */
    fun onDisplayChanged() {
        if (released) return
        val size = computeSize()
        if (size.w == frameWidth && size.h == frameHeight) {
            apply(size)
            return
        }
        handler.post {
            if (released) return@post
            val old = reader
            val r = newReader(size.w, size.h)
            reader = r
            display?.resize(size.w, size.h, size.dpi)
            display?.surface = r.surface
            apply(size)
            pending?.complete(null)
            pending = null
            old?.close()
            reusable?.recycle()
            reusable = null
        }
    }

    /**
     * Aguarda o próximo frame novo (a tela só gera frames quando muda).
     * Retorna nulo se nada mudou dentro de [timeoutMs].
     */
    suspend fun nextFrame(timeoutMs: Long): CapturedFrame? {
        if (released) return null
        val deferred = CompletableDeferred<CapturedFrame?>()
        pending = deferred
        val result = withTimeoutOrNull(timeoutMs) { deferred.await() }
        if (result == null) {
            pending = null
            deferred.cancel()
        }
        return result
    }

    private fun newReader(w: Int, h: Int): ImageReader =
        ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2).also { r ->
            r.setOnImageAvailableListener({ onImage(it) }, handler)
        }

    private fun onImage(r: ImageReader) {
        val image = try {
            r.acquireLatestImage()
        } catch (e: IllegalStateException) {
            null
        } ?: return
        try {
            val target = pending ?: return
            if (target.isCompleted) return
            val plane = image.planes[0]
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val paddedWidth = rowStride / pixelStride
            val bmp = reusable?.takeIf { it.width == paddedWidth && it.height == image.height && !it.isRecycled }
                ?: try {
                    Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888).also {
                        reusable?.recycle()
                        reusable = it
                    }
                } catch (oom: OutOfMemoryError) {
                    Log.w(TAG, "Sem memória para o frame; descartando", oom)
                    target.complete(null)
                    pending = null
                    return
                }
            plane.buffer.rewind()
            bmp.copyPixelsFromBuffer(plane.buffer)
            pending = null
            target.complete(CapturedFrame(bmp, scale, screenWidth, screenHeight))
        } catch (t: Throwable) {
            Log.w(TAG, "Falha ao converter frame", t)
        } finally {
            image.close()
        }
    }

    fun release(stopProjection: Boolean) {
        if (released) return
        released = true
        pending?.complete(null)
        pending = null
        handler.post {
            try {
                display?.release()
            } catch (_: Throwable) {}
            display = null
            reader?.close()
            reader = null
            try {
                projection.unregisterCallback(callback)
            } catch (_: Throwable) {}
            if (stopProjection) {
                try {
                    projection.stop()
                } catch (_: Throwable) {}
            }
            // O bitmap reutilizável pode estar em uso pelo OCR; deixamos para o GC.
            reusable = null
            thread.quitSafely()
        }
    }

    private data class Size(val w: Int, val h: Int, val dpi: Int, val screenW: Int, val screenH: Int)

    private fun apply(size: Size) {
        frameWidth = size.w
        frameHeight = size.h
        screenWidth = size.screenW
        screenHeight = size.screenH
        scale = size.w.toFloat() / size.screenW.coerceAtLeast(1)
    }

    @SuppressLint("NewApi")
    private fun computeSize(): Size {
        val (sw, sh) = screenSize(context)
        val dpi = context.resources.displayMetrics.densityDpi
        val s = if (sw > maxWidth) maxWidth.toFloat() / sw else 1f
        // Dimensões pares evitam problemas em alguns encoders/surfaces.
        val w = ((sw * s).roundToInt() / 2) * 2
        val h = ((sh * s).roundToInt() / 2) * 2
        return Size(w.coerceAtLeast(2), h.coerceAtLeast(2), dpi, sw, sh)
    }

    companion object {
        private const val TAG = "ScreenCapture"

        /** Tamanho físico atual da tela (inclui barras do sistema). [context] deve ser um contexto de janela. */
        fun screenSize(context: Context): Pair<Int, Int> {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val wm = context.getSystemService(WindowManager::class.java)
                val b = wm.maximumWindowMetrics.bounds
                b.width() to b.height()
            } else {
                val dm = context.getSystemService(DisplayManager::class.java)
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                dm.getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(metrics)
                metrics.widthPixels to metrics.heightPixels
            }
        }

        /**
         * Contexto de janela para sobreposição (Android 11+). Evita o uso de WindowManager
         * a partir de um contexto não visual (Service), que o sistema sinaliza como incorreto.
         */
        fun windowContext(base: Context): Context {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return base
            val dm = base.getSystemService(DisplayManager::class.java)
            val display = dm.getDisplay(Display.DEFAULT_DISPLAY)
            return base.createDisplayContext(display)
                .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
        }
    }
}
