package com.driverintelligence.domain.overlay

enum class OverlayMode { MINIMIZED, COMPACT, EXPANDED }

enum class OverlayAction { MINIMIZE, EXPAND, COLLAPSE, TOGGLE }

/** Regras puras do overlay: transição de modos e geometria (testáveis sem Android). */
object OverlayLogic {

    fun nextMode(current: OverlayMode, action: OverlayAction): OverlayMode = when (action) {
        OverlayAction.MINIMIZE -> OverlayMode.MINIMIZED
        OverlayAction.EXPAND -> OverlayMode.EXPANDED
        OverlayAction.COLLAPSE -> OverlayMode.COMPACT
        OverlayAction.TOGGLE -> when (current) {
            OverlayMode.MINIMIZED -> OverlayMode.COMPACT
            OverlayMode.COMPACT -> OverlayMode.EXPANDED
            OverlayMode.EXPANDED -> OverlayMode.COMPACT
        }
    }

    /** Mantém a janela inteira visível, com margem, mesmo após rotação ou mudança de resolução. */
    fun clamp(x: Int, y: Int, viewW: Int, viewH: Int, screenW: Int, screenH: Int, margin: Int = 0): Pair<Int, Int> {
        val maxX = (screenW - viewW - margin).coerceAtLeast(margin)
        val maxY = (screenH - viewH - margin).coerceAtLeast(margin)
        return x.coerceIn(margin, maxX) to y.coerceIn(margin, maxY)
    }

    /** Posição relativa (0..1) — persiste bem entre orientações e resoluções. */
    fun toRelative(x: Int, y: Int, viewW: Int, viewH: Int, screenW: Int, screenH: Int): Pair<Float, Float> {
        val rangeX = (screenW - viewW).coerceAtLeast(1)
        val rangeY = (screenH - viewH).coerceAtLeast(1)
        return (x.toFloat() / rangeX).coerceIn(0f, 1f) to (y.toFloat() / rangeY).coerceIn(0f, 1f)
    }

    fun fromRelative(rx: Float, ry: Float, viewW: Int, viewH: Int, screenW: Int, screenH: Int): Pair<Int, Int> {
        val rangeX = (screenW - viewW).coerceAtLeast(0)
        val rangeY = (screenH - viewH).coerceAtLeast(0)
        return (rx.coerceIn(0f, 1f) * rangeX).toInt() to (ry.coerceIn(0f, 1f) * rangeY).toInt()
    }

    /** Converte o retângulo do overlay (tela) para coordenadas do frame capturado (possivelmente reduzido). */
    fun scaleRect(left: Int, top: Int, right: Int, bottom: Int, scale: Float, padding: Int = 0): IntArray =
        intArrayOf(
            ((left - padding) * scale).toInt().coerceAtLeast(0),
            ((top - padding) * scale).toInt().coerceAtLeast(0),
            ((right + padding) * scale).toInt(),
            ((bottom + padding) * scale).toInt(),
        )
}
