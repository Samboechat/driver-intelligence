package com.driverintelligence.recognition

import android.graphics.Bitmap
import com.driverintelligence.domain.recognition.Box
import com.driverintelligence.domain.recognition.OcrFrame
import com.driverintelligence.domain.recognition.OcrLine
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Abstração do OCR — permite trocar o motor e testar o pipeline sem ML Kit. */
interface OcrEngine {
    /**
     * Reconhece o texto do bitmap. O chamador NÃO deve reciclar o bitmap se a chamada
     * for cancelada (o reconhecimento pode ainda estar lendo os pixels).
     */
    suspend fun recognize(bitmap: Bitmap): OcrFrame
    fun close()
}

/** ML Kit Text Recognition (latino), com modelo embarcado no APK: processamento 100% local. */
class MlKitOcrEngine : OcrEngine {

    private var recognizer: TextRecognizer? = null

    private fun client(): TextRecognizer =
        recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { recognizer = it }

    override suspend fun recognize(bitmap: Bitmap): OcrFrame = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        val width = bitmap.width
        val height = bitmap.height
        client().process(image)
            .addOnSuccessListener { text -> if (cont.isActive) cont.resume(text.toFrame(width, height)) }
            .addOnFailureListener { e -> if (cont.isActive) cont.resumeWithException(e) }
    }

    override fun close() {
        recognizer?.close()
        recognizer = null
    }
}

internal fun Text.toFrame(width: Int, height: Int): OcrFrame = OcrFrame(
    lines = textBlocks.flatMap { block ->
        block.lines.map { line ->
            OcrLine(line.text, line.boundingBox?.let { Box(it.left, it.top, it.right, it.bottom) })
        }
    },
    width = width,
    height = height,
)
