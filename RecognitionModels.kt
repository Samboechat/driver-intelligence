package com.driverintelligence.domain.recognition

import com.driverintelligence.domain.model.OfferData

/** Retângulo em pixels da imagem processada. */
data class Box(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val height: Int get() = bottom - top
    val width: Int get() = right - left
    val centerY: Int get() = (top + bottom) / 2
    fun intersects(other: Box): Boolean =
        left < other.right && other.left < right && top < other.bottom && other.top < bottom
}

/** Linha de texto reconhecida. [box] é opcional (texto colado manualmente não tem geometria). */
data class OcrLine(val text: String, val box: Box? = null)

data class OcrFrame(
    val lines: List<OcrLine>,
    val width: Int = 0,
    val height: Int = 0,
) {
    companion object {
        fun fromText(text: String): OcrFrame = OcrFrame(text.lines().filter { it.isNotBlank() }.map { OcrLine(it.trim()) })
    }
}

enum class PairLabel { PICKUP, TRIP, UNLABELED }

/** Par tempo + distância encontrado no texto ("4 min (1,2 km)"). */
data class TimeDistancePair(
    val minutes: Double?,
    val km: Double,
    val label: PairLabel,
    val startIndex: Int,
    val lineIndex: Int,
)

data class ParseResult(
    val offer: OfferData,
    /** Confiança 0..1 na leitura (não na rentabilidade). */
    val confidence: Double,
    /** A tela parece ser uma oferta de corrida. */
    val isOfferScreen: Boolean,
    /** Ordem busca/viagem deduzida por posição, sem rótulo explícito. */
    val orderInferred: Boolean,
    val fareAmbiguous: Boolean,
    val ocrCorrections: Int,
    val notes: List<String>,
)
