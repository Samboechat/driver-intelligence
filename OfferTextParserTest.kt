package com.driverintelligence.domain.recognition

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Testes do parser com textos de oferta em vários formatos. Os textos são representativos
 * do layout do Uber Driver no Brasil; ajuste com capturas reais pelo Laboratório OCR do app.
 */
class OfferTextParserTest {

    private val parser = OfferTextParser()
    private fun parse(text: String) = parser.parse(OcrFrame.fromText(text.trimIndent()))

    @Test
    fun cartaoPadraoBrasil() {
        val r = parse(
            """
            UberX
            R$ 18,50
            ★ 4,92
            4 min (1,2 km) de distância
            Rua das Flores, 120 - Centro
            Viagem: 20 min (9,3 km)
            Av. Paulista, 1000 - Bela Vista
            Aceitar
            """,
        )
        val o = r.offer
        assertEquals(18.5, o.fare!!, 1e-9)
        assertEquals(1.2, o.pickupDistanceKm!!, 1e-9)
        assertEquals(4.0, o.pickupTimeMin!!, 1e-9)
        assertEquals(9.3, o.tripDistanceKm!!, 1e-9)
        assertEquals(20.0, o.tripTimeMin!!, 1e-9)
        assertEquals("UberX", o.category)
        assertEquals(4.92, o.passengerRating!!, 1e-9)
        assertEquals("Rua das Flores, 120 - Centro", o.origin)
        assertEquals("Av. Paulista, 1000 - Bela Vista", o.destination)
        assertTrue(r.isOfferScreen)
        assertFalse(r.orderInferred)
        assertEquals(1.0, r.confidence, 1e-9)
    }

    @Test
    fun quebrasDeLinhaNoMeioDosPares() {
        val r = parse(
            """
            R$ 18,50
            4 min (1,2 km)
            de distância
            Viagem
            20 min
            (9,3 km)
            Aceitar
            """,
        )
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(9.3, r.offer.tripDistanceKm!!, 1e-9)
        assertEquals(20.0, r.offer.tripTimeMin!!, 1e-9)
        assertFalse(r.orderInferred)
    }

    @Test
    fun separadorDecimalPontoEPrefixoComEspaco() {
        val r = parse(
            """
            R $ 18.50
            4 min (1.2 km) de distância
            Viagem de 20 min (9.3 km)
            """,
        )
        assertEquals(18.5, r.offer.fare!!, 1e-9)
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(9.3, r.offer.tripDistanceKm!!, 1e-9)
    }

    @Test
    fun formatoEmInglesComMilhas() {
        val r = parse(
            """
            ${'$'}18.50
            4 mins (1.2 mi) away
            20 min (9.3 mi) trip
            Accept
            """,
        )
        assertEquals(18.5, r.offer.fare!!, 1e-9)
        assertEquals(1.2 * 1.609344, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(9.3 * 1.609344, r.offer.tripDistanceKm!!, 1e-9)
        assertEquals(4.0, r.offer.pickupTimeMin!!, 1e-9)
    }

    @Test
    fun distanciaEmMetrosETempoEmHoras() {
        val r = parse(
            """
            R$ 62,40
            3 min (800 m) de distância
            Viagem: 1 h 05 min (48,2 km)
            """,
        )
        assertEquals(0.8, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(65.0, r.offer.tripTimeMin!!, 1e-9)
        assertEquals(48.2, r.offer.tripDistanceKm!!, 1e-9)
    }

    @Test
    fun valorDoDiaNoTopo_naoEhConfundidoComOValorDaCorrida() {
        val r = parse(
            """
            R$ 152,30
            UberX
            R$ 18,50
            4 min (1,2 km) de distância
            Viagem: 20 min (9,3 km)
            """,
        )
        assertEquals(18.5, r.offer.fare!!, 1e-9)
    }

    @Test
    fun geometria_maiorTextoProximoDosParesEhOValor() {
        val frame = OcrFrame(
            lines = listOf(
                OcrLine("R$ 152,30", Box(400, 80, 680, 130)),
                OcrLine("R$ 18,50", Box(80, 1500, 600, 1640)),
                OcrLine("4 min (1,2 km) de distância", Box(80, 1700, 900, 1760)),
                OcrLine("Viagem: 20 min (9,3 km)", Box(80, 1860, 900, 1920)),
            ),
            width = 1080,
            height = 2400,
        )
        val r = parser.parse(frame)
        assertEquals(18.5, r.offer.fare!!, 1e-9)
        assertFalse(r.fareAmbiguous)
    }

    @Test
    fun dinamicoEBonusNaoSaoOValor() {
        val r = parse(
            """
            R$ 21,50
            +R$ 3,00
            Inclui R$ 2,50 de dinâmico
            4 min (1,2 km) de distância
            Viagem: 20 min (9,3 km)
            """,
        )
        assertEquals(21.5, r.offer.fare!!, 1e-9)
        assertEquals(3.0, r.offer.surgeAmount!!, 1e-9)
    }

    @Test
    fun valorPorKmExibidoPeloApp() {
        val r = parse(
            """
            R$ 18,50
            R$ 1,76/km
            4 min (1,2 km) de distância
            Viagem: 20 min (9,3 km)
            """,
        )
        assertEquals(18.5, r.offer.fare!!, 1e-9)
        assertEquals(1.76, r.offer.displayedRatePerKm!!, 1e-9)
    }

    @Test
    fun confusoesDoOcrSaoCorrigidasComPenalidade() {
        val r = parse(
            """
            R$ 1O,5O
            4 min (l,2 km) de distância
            Viagem: 20 min (9,3 km)
            """,
        )
        assertEquals(10.5, r.offer.fare!!, 1e-9)
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(3, r.ocrCorrections)
        assertTrue(r.confidence < 1.0)
    }

    @Test
    fun ofertaParcialmenteVisivel() {
        val r = parse(
            """
            R$ 18,50
            4 min (1,2 km) de distância
            """,
        )
        assertTrue(r.isOfferScreen)
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertNull(r.offer.tripDistanceKm)
        assertTrue(r.confidence < 0.7)
    }

    @Test
    fun telaSemOferta() {
        val r = parse(
            """
            Você está online
            Procurando viagens
            R$ 152,30
            """,
        )
        assertFalse(r.isOfferScreen)
    }

    @Test
    fun paresSemRotulo_ordemDeduzida() {
        val r = parse(
            """
            R$ 18,50
            4 min (1,2 km)
            20 min (9,3 km)
            """,
        )
        assertTrue(r.orderInferred)
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(9.3, r.offer.tripDistanceKm!!, 1e-9)
        assertTrue(r.confidence < 1.0)
    }

    @Test
    fun layoutComDistanciaAntesDoTempo() {
        val r = parse(
            """
            R$ 18,50
            1,2 km · 4 min de distância
            Viagem: 9,3 km · 20 min
            """,
        )
        assertEquals(1.2, r.offer.pickupDistanceKm!!, 1e-9)
        assertEquals(4.0, r.offer.pickupTimeMin!!, 1e-9)
        assertEquals(9.3, r.offer.tripDistanceKm!!, 1e-9)
        assertEquals(20.0, r.offer.tripTimeMin!!, 1e-9)
    }

    @Test
    fun linhasDoProprioOverlaySaoIgnoradas() {
        val r = parse(
            """
            DRIVER INTELLIGENCE
            R$ 99,00
            """,
        )
        assertFalse(r.isOfferScreen)
    }

    @Test
    fun categoriasConhecidas() {
        assertEquals("Comfort", parse("Comfort\nR$ 30,00\n4 min (1,2 km) de distância").offer.category)
        assertEquals("Black", parse("Uber Black\nR$ 30,00\n4 min (1,2 km) de distância").offer.category)
        assertEquals("Flash", parse("Uber Flash\nR$ 30,00\n4 min (1,2 km) de distância").offer.category)
    }
}
