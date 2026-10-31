package com.driverintelligence.domain.recognition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NumberNormalizerTest {

    private fun p(s: String, hint: Boolean = false) = NumberNormalizer.parse(s, hint)

    @Test
    fun formatosBrasileiros() {
        assertEquals(18.5, p("18,50")!!, 1e-9)
        assertEquals(8.4, p("8,4")!!, 1e-9)
        assertEquals(1234.56, p("1.234,56")!!, 1e-9)
        assertEquals(24.0, p("24")!!, 1e-9)
    }

    @Test
    fun formatosInternacionais() {
        assertEquals(18.5, p("18.50")!!, 1e-9)
        assertEquals(1234.56, p("1,234.56")!!, 1e-9)
        assertEquals(8.4, p("8.4")!!, 1e-9)
    }

    @Test
    fun milharAmbiguo_usaDica() {
        assertEquals(1.234, p("1.234")!!, 1e-9)
        assertEquals(1234.0, p("1.234", hint = true)!!, 1e-9)
        assertEquals(1234567.0, p("1.234.567")!!, 1e-9)
    }

    @Test
    fun espacosEInvalidos() {
        assertEquals(18.5, p(" 18 ,50 ")!!, 1e-9)
        assertEquals(18.5, p("18 ,50")!!, 1e-9)
        assertNull(p(""))
        assertNull(p("abc"))
        assertNull(p("12a"))
        assertNull(p(","))
    }

    @Test
    fun correcaoDeConfusoesDoOcr() {
        val (fixed, n) = NumberNormalizer.fixDigitConfusions("R$ 1O,5O")
        assertEquals("R$ 10,50", fixed)
        assertEquals(2, n)
        val (fixed2, n2) = NumberNormalizer.fixDigitConfusions("4 min (l,2 km)")
        assertEquals("4 min (1,2 km)", fixed2)
        assertEquals(1, n2)
    }

    @Test
    fun correcaoNaoAlteraPalavras() {
        val text = "Inclui Dinâmico Bola Olá"
        val (fixed, n) = NumberNormalizer.fixDigitConfusions(text)
        assertEquals(text, fixed)
        assertEquals(0, n)
    }
}
