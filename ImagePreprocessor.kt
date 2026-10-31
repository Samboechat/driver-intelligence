package com.driverintelligence.recognition

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import com.driverintelligence.domain.model.CaptureRegion

/**
 * Pré-processamento antes do OCR:
 *  1. Máscara sobre a área do próprio overlay (evita ler os números do Driver Intelligence como oferta).
 *  2. Recorte da região de interesse (opcional, reduz CPU).
 *  3. Escala de cinza + contraste (opcional, ajuda em telas com baixo contraste).
 *
 * Reaproveita bitmaps de saída entre frames para reduzir alocações.
 */
class ImagePreprocessor {

    private var enhanced: Bitmap? = null
    private val maskPaint = Paint().apply { color = android.graphics.Color.BLACK }
    private val contrastPaint = Paint(Paint.FILTER_BITMAP_FLAG).apply {
        val contrast = 1.6f
        val translate = (-0.5f * contrast + 0.5f) * 255f
        val gray = ColorMatrix().apply { setSaturation(0f) }
        val boost = ColorMatrix(
            floatArrayOf(
                contrast, 0f, 0f, 0f, translate,
                0f, contrast, 0f, 0f, translate,
                0f, 0f, contrast, 0f, translate,
                0f, 0f, 0f, 1f, 0f,
            ),
        )
        gray.postConcat(boost)
        colorFilter = ColorMatrixColorFilter(gray)
    }

    data class Prepared(val bitmap: Bitmap, val offsetY: Int, val owned: Boolean)

    /**
     * @param source bitmap mutável do frame (será alterado pela máscara).
     * @param mask retângulo do overlay em coordenadas do frame, ou nulo.
     */
    fun prepare(source: Bitmap, region: CaptureRegion, mask: Rect?, enhanceContrast: Boolean): Prepared {
        if (mask != null && source.isMutable) {
            val clipped = Rect(mask)
            if (clipped.intersect(0, 0, source.width, source.height)) {
                Canvas(source).drawRect(clipped, maskPaint)
            }
        }
        val offsetY = if (region == CaptureRegion.BOTTOM_HALF) source.height / 2 else 0
        val cropped = if (offsetY > 0) {
            Bitmap.createBitmap(source, 0, offsetY, source.width, source.height - offsetY)
        } else source

        if (!enhanceContrast) return Prepared(cropped, offsetY, owned = cropped !== source)

        val out = enhanced?.takeIf { it.width == cropped.width && it.height == cropped.height && !it.isRecycled }
            ?: Bitmap.createBitmap(cropped.width, cropped.height, Bitmap.Config.ARGB_8888).also {
                enhanced?.recycle()
                enhanced = it
            }
        Canvas(out).drawBitmap(cropped, 0f, 0f, contrastPaint)
        if (cropped !== source) cropped.recycle()
        return Prepared(out, offsetY, owned = false)
    }

    fun release() {
        enhanced?.recycle()
        enhanced = null
    }

    companion object {
        /**
         * Frame quase todo preto: típico de app que bloqueia captura (FLAG_SECURE),
         * de tela apagada ou de projeção interrompida.
         */
        fun isMostlyBlack(bitmap: Bitmap, threshold: Float = 0.97f): Boolean {
            val stepsX = 16
            val stepsY = 24
            var dark = 0
            var total = 0
            for (iy in 1..stepsY) {
                val y = (bitmap.height * iy / (stepsY + 1)).coerceIn(0, bitmap.height - 1)
                for (ix in 1..stepsX) {
                    val x = (bitmap.width * ix / (stepsX + 1)).coerceIn(0, bitmap.width - 1)
                    val p = bitmap.getPixel(x, y)
                    val r = (p shr 16) and 0xFF
                    val g = (p shr 8) and 0xFF
                    val b = p and 0xFF
                    if (r + g + b < 24) dark++
                    total++
                }
            }
            return total > 0 && dark.toFloat() / total >= threshold
        }
    }
}
