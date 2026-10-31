package com.driverintelligence.domain.recognition

import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.OfferData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OfferValidatorAndAnalyzerTest {

    private val validator = OfferValidator()
    private val analyzer = OfferAnalyzer()
    private val ctx = AnalysisContext(costs = CostProfile(consumptionKmPerUnit = 11.0, energyPricePerUnit = 6.2))

    @Test
    fun ofertaValida() {
        val v = validator.validate(OfferData(18.5, 1.2, 9.3, 4.0, 20.0))
        assertEquals(ValidationStatus.VALID, v.status)
        assertEquals(1.0, v.confidenceFactor, 1e-9)
    }

    @Test
    fun camposEssenciaisAusentes_incompleta() {
        val v = validator.validate(OfferData(fare = 18.5, tripDistanceKm = 9.3))
        assertEquals(ValidationStatus.INCOMPLETE, v.status)
        assertTrue(v.issues.any { it.message.contains("distância até o embarque") })
    }

    @Test
    fun foraDaFaixa_invalida() {
        val v = validator.validate(OfferData(18.5, 1.2, 9.3, 4.0, 2000.0))
        assertEquals(ValidationStatus.INVALID, v.status)
        assertTrue(v.confidenceFactor <= 0.5)
    }

    @Test
    fun velocidadeIncoerente_reduzConfianca() {
        val v = validator.validate(OfferData(18.5, 1.2, 93.0, 4.0, 20.0)) // 279 km/h
        assertTrue(v.issues.any { it.message.contains("incoerentes") })
        assertTrue(v.confidenceFactor < 1.0)
    }

    @Test
    fun valorPorKmImprovavel() {
        val v = validator.validate(OfferData(185.0, 1.2, 3.0, 4.0, 10.0)) // R$ 44/km
        assertTrue(v.issues.any { it.message.contains("improvável") })
    }

    @Test
    fun fluxoCompleto_textoParaClassificacao() {
        val frame = OcrFrame.fromText(
            "UberX\nR$ 18,50\n4 min (1,2 km) de distância\nRua A\nViagem: 20 min (9,3 km)\nRua B\nAceitar",
        )
        val fa = analyzer.analyzeFrame(frame, ctx)
        assertTrue(fa.isOfferScreen)
        val a = fa.analysis!!
        assertEquals(Classification.GREEN, a.decision.classification)
        assertEquals(1.0, a.confidence, 1e-9)
        assertEquals("1850|12|93|20", a.fingerprint)
    }

    @Test
    fun leituraInconsistente_naoGeraRecomendacao() {
        val frame = OcrFrame.fromText("R$ 18,50\n4 min (1,2 km) de distância\nViagem: 20 min (930 km)")
        val a = analyzer.analyzeFrame(frame, ctx).analysis!!
        assertEquals(Classification.GRAY, a.decision.classification)
    }

    @Test
    fun telaSemOferta_semAnalise() {
        val fa = analyzer.analyzeFrame(OcrFrame.fromText("Você está online"), ctx)
        assertFalse(fa.isOfferScreen)
        assertNull(fa.analysis)
    }

    @Test
    fun impressaoDigital_estavelEDistinta() {
        val a = OfferAnalyzer.fingerprint(OfferData(18.5, 1.2, 9.3, 4.0, 20.0))
        val b = OfferAnalyzer.fingerprint(OfferData(18.5, 1.2, 9.3, 4.0, 20.0, origin = "outra leitura"))
        val c = OfferAnalyzer.fingerprint(OfferData(19.0, 1.2, 9.3, 4.0, 20.0))
        assertEquals(a, b)
        assertNotEquals(a, c)
        assertNull(OfferAnalyzer.fingerprint(OfferData(fare = 18.5)))
    }

    @Test
    fun entradaManual_temConfiancaAlta() {
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), ctx)
        assertTrue(a.confidence >= 0.9)
        assertNull(a.parse)
        assertEquals(Classification.GREEN, a.decision.classification)
    }
}
