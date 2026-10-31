package com.driverintelligence.recognition

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.driverintelligence.domain.recognition.OfferTextParser
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Teste instrumentado (exige aparelho ou emulador): renderiza cartões de oferta sintéticos
 * em resoluções e contrastes diferentes e verifica a leitura completa ML Kit → parser.
 *
 * Não substitui testes com capturas reais do Uber Driver — use o Laboratório de OCR para isso.
 */
@RunWith(AndroidJUnit4::class)
class SyntheticOfferOcrTest {

    private val ocr = MlKitOcrEngine()
    private val parser = OfferTextParser()

    private val lines = listOf(
        "UberX" to 34f,
        "R$ 18,50" to 72f,
        "4 min (1,2 km) de distância" to 34f,
        "Rua das Flores, 120 - Centro" to 30f,
        "Viagem: 20 min (9,3 km)" to 34f,
        "Av. Paulista, 1000 - Bela Vista" to 30f,
        "Aceitar" to 40f,
    )

    private fun render(width: Int, scale: Float, background: Int, foreground: Int): Bitmap {
        val height = (width * 2.2f).toInt()
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(background)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = foreground
            typeface = Typeface.DEFAULT_BOLD
        }
        var y = height * 0.45f
        for ((text, size) in lines) {
            paint.textSize = size * scale
            canvas.drawText(text, width * 0.06f, y, paint)
            y += size * scale * 1.7f
        }
        return bmp
    }

    private suspend fun check(width: Int, scale: Float, bg: Int, fg: Int) {
        val frame = ocr.recognize(render(width, scale, bg, fg))
        val r = parser.parse(frame)
        assertTrue("oferta não detectada em ${width}px", r.isOfferScreen)
        assertEquals(18.5, r.offer.fare!!, 1e-6)
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-6)
        assertEquals(9.3, r.offer.tripDistanceKm!!, 1e-6)
        assertEquals(20.0, r.offer.tripTimeMin!!, 1e-6)
    }

    @Test fun resolucaoAlta_temaEscuro() = runTest { check(1080, 1.0f, Color.BLACK, Color.WHITE) }
    @Test fun resolucaoMedia_temaClaro() = runTest { check(720, 0.67f, Color.WHITE, Color.BLACK) }
    @Test fun resolucaoBaixa() = runTest { check(540, 0.5f, Color.rgb(20, 20, 20), Color.rgb(235, 235, 235)) }
    @Test fun baixoContraste() = runTest { check(1080, 1.0f, Color.rgb(40, 40, 40), Color.rgb(140, 140, 140)) }

    @After
    fun tearDown() = ocr.close()
}
