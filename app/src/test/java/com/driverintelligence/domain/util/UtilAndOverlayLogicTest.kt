package com.driverintelligence.domain.util

import com.driverintelligence.domain.overlay.OverlayAction
import com.driverintelligence.domain.overlay.OverlayLogic
import com.driverintelligence.domain.overlay.OverlayMode
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UtilAndOverlayLogicTest {

    @Test
    fun formatacaoBrasileira() {
        assertEquals("R$ 18,50", Br.money(18.5))
        assertEquals("R$ 1.234,56", Br.money(1234.56))
        assertEquals("−R$ 2,30", Br.money(-2.3))
        assertEquals("R$ 1,76/km", Br.perKm(18.5 / 10.5))
        assertEquals("R$ 46,25/h", Br.perHour(46.25))
        assertEquals("10,5 km", Br.km(10.5))
        assertEquals("24 min", Br.minutes(24.0))
        assertEquals("1 h 05 min", Br.minutes(65.0))
        assertEquals("2 h", Br.minutes(120.0))
        assertEquals("35%", Br.percent(0.35))
        assertEquals("—", Br.money(null))
        assertEquals("—", Br.money(Double.NaN))
    }

    @Test
    fun csvEscapaSeparadoresAspasEFormulas() {
        val csv = Csv.write(listOf("a", "b"), listOf(listOf("x;y", "diz \"oi\""), listOf("=SOMA(A1)", "-3,50")))
        assertTrue(csv.startsWith(Csv.BOM))
        val lines = csv.removePrefix(Csv.BOM).split("\r\n")
        assertEquals("a;b", lines[0])
        assertEquals("\"x;y\";\"diz \"\"oi\"\"\"", lines[1])
        assertEquals("'=SOMA(A1);-3,50", lines[2])
    }

    @Test
    fun overlay_transicoesDeModo() {
        assertEquals(OverlayMode.MINIMIZED, OverlayLogic.nextMode(OverlayMode.EXPANDED, OverlayAction.MINIMIZE))
        assertEquals(OverlayMode.COMPACT, OverlayLogic.nextMode(OverlayMode.MINIMIZED, OverlayAction.TOGGLE))
        assertEquals(OverlayMode.EXPANDED, OverlayLogic.nextMode(OverlayMode.COMPACT, OverlayAction.TOGGLE))
        assertEquals(OverlayMode.COMPACT, OverlayLogic.nextMode(OverlayMode.EXPANDED, OverlayAction.TOGGLE))
        assertEquals(OverlayMode.COMPACT, OverlayLogic.nextMode(OverlayMode.EXPANDED, OverlayAction.COLLAPSE))
        assertEquals(OverlayMode.EXPANDED, OverlayLogic.nextMode(OverlayMode.MINIMIZED, OverlayAction.EXPAND))
    }

    @Test
    fun overlay_arrasteLimitadoATela() {
        assertEquals(16 to 16, OverlayLogic.clamp(-200, -50, 300, 200, 1080, 2400, 16))
        assertEquals(764 to 2184, OverlayLogic.clamp(5000, 5000, 300, 200, 1080, 2400, 16))
        assertEquals(400 to 900, OverlayLogic.clamp(400, 900, 300, 200, 1080, 2400, 16))
    }

    @Test
    fun overlay_posicaoSobreviveARotacao() {
        val (rx, ry) = OverlayLogic.toRelative(780, 2200, 300, 200, 1080, 2400)
        assertEquals(1f, rx, 1e-3f)
        assertEquals(1f, ry, 1e-3f)
        // Paisagem: mesma posição relativa, dentro da nova tela.
        val (x, y) = OverlayLogic.fromRelative(rx, ry, 300, 200, 2400, 1080)
        assertEquals(2100, x)
        assertEquals(880, y)
    }

    @Test
    fun overlay_retanguloEscalonadoParaOFrame() {
        assertArrayEquals(intArrayOf(45, 95, 255, 205), OverlayLogic.scaleRect(100, 200, 500, 400, 0.5f, padding = 10))
        assertArrayEquals(intArrayOf(0, 0, 25, 25), OverlayLogic.scaleRect(0, 0, 40, 40, 0.5f, padding = 10))
    }
}
