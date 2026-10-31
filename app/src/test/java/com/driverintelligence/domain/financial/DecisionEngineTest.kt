package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.Metric
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.ScoringConfig
import com.driverintelligence.domain.model.ScoringWeights
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DecisionEngineTest {

    private val fin = FinancialEngine()
    private val engine = DecisionEngine()
    private val fuelOnly = CostProfile(consumptionKmPerUnit = 11.0, energyPricePerUnit = 6.20)
    private val full = CostProfile(11.0, 6.20, 0.08, 0.05, 0.02, 0.12)

    private fun decide(offer: OfferData, costs: CostProfile = fuelOnly, goals: Goals = Goals(), config: ScoringConfig = ScoringConfig(), conf: Double? = null) =
        engine.decide(fin.calculate(offer, costs), goals, config, conf)

    @Test
    fun curvaDePontuacao() {
        assertEquals(0.0, DecisionEngine.scoreHigherIsBetter(0.5, 1.0), 1e-9)
        assertEquals(0.0, DecisionEngine.scoreHigherIsBetter(0.6, 1.0), 1e-9)
        assertEquals(0.35, DecisionEngine.scoreHigherIsBetter(0.8, 1.0), 1e-9)
        assertEquals(0.7, DecisionEngine.scoreHigherIsBetter(1.0, 1.0), 1e-9)
        assertEquals(1.0, DecisionEngine.scoreHigherIsBetter(1.25, 1.0), 1e-9)
        assertEquals(1.0, DecisionEngine.scoreHigherIsBetter(3.0, 1.0), 1e-9)
        assertEquals(1.0, DecisionEngine.scoreLowerIsBetter(0.0, 10.0), 1e-9)
        assertEquals(0.7, DecisionEngine.scoreLowerIsBetter(10.0, 10.0), 1e-9)
        assertEquals(0.0, DecisionEngine.scoreLowerIsBetter(20.0, 10.0), 1e-9)
    }

    @Test
    fun ofertaBoa_verdeComJustificativa() {
        val d = decide(OfferData(18.50, 1.2, 9.3, 4.0, 20.0))
        assertEquals(Classification.GREEN, d.classification)
        assertEquals("Boa rentabilidade: R$ 1,76/km e R$ 46,25/h.", d.headline)
        assertTrue(d.isPartial) // só combustível configurado
        assertTrue(d.reasons.any { it.startsWith("Estimativa parcial") })
        assertEquals(7, d.metricScores.size)
    }

    @Test
    fun ofertaRuim_vermelha() {
        val d = decide(OfferData(7.0, 6.0, 3.0, 15.0, 9.0), full)
        assertEquals(Classification.RED, d.classification)
        assertTrue(d.headline.startsWith("Não recomendada: "))
    }

    @Test
    fun justificativaComDistanciaDeBuscaELucroAbaixoDaMeta() {
        // Pesos favorecem a distância de busca para reproduzir a mensagem da especificação.
        val weights = ScoringWeights(0.1, 0.0, 0.1, 0.0, 0.0, 0.8, 0.0)
        val d = decide(
            OfferData(16.0, 7.0, 6.0, 14.0, 14.0),
            full,
            Goals(minProfitPerTrip = 12.0),
            ScoringConfig(weights = weights),
        )
        assertEquals(Classification.RED, d.classification)
        assertEquals("Não recomendada: distância de busca elevada e lucro estimado abaixo da sua meta.", d.headline)
    }

    @Test
    fun prejuizoEstimado_sempreVermelho() {
        // Valor/km e valor/hora altos o suficiente, mas custos maiores que o valor.
        val costly = CostProfile(operationalCostPerKmOverride = 3.0, operationalCostIncludesFuel = true)
        val d = decide(OfferData(25.0, 0.5, 9.5, 2.0, 15.0), costly, Goals(minRevenuePerKm = 1.0, minRevenuePerHour = 30.0))
        assertEquals(Classification.RED, d.classification)
        assertTrue(d.headline.contains("prejuízo estimado"))
    }

    @Test
    fun lucroMinimoPorCorrida_rebaixaVerdeParaAmarelo() {
        val offer = OfferData(18.50, 1.2, 9.3, 4.0, 20.0)
        assertEquals(Classification.GREEN, decide(offer).classification)
        val d = decide(offer, goals = Goals(minProfitPerTrip = 20.0))
        assertEquals(Classification.YELLOW, d.classification)
        assertTrue(d.headline.contains("lucro estimado abaixo da sua meta"))
    }

    @Test
    fun distanciaTotalAcimaDoLimite_rebaixaVerde() {
        val offer = OfferData(80.0, 1.0, 35.0, 3.0, 40.0)
        assertEquals(Classification.GREEN, decide(offer).classification)
        assertEquals(Classification.YELLOW, decide(offer, goals = Goals(maxTotalDistanceKm = 25.0)).classification)
    }

    @Test
    fun dadosEssenciaisAusentes_cinza() {
        val d = decide(OfferData(fare = 18.5, tripDistanceKm = 9.3))
        assertEquals(Classification.GRAY, d.classification)
        assertNull(d.score)
        assertTrue(d.headline.contains("distância até o embarque"))
    }

    @Test
    fun confiancaBaixa_cinza() {
        val d = decide(OfferData(18.50, 1.2, 9.3, 4.0, 20.0), conf = 0.4)
        assertEquals(Classification.GRAY, d.classification)
        assertTrue(d.headline.contains("40%"))
    }

    @Test
    fun semTempos_usaSoIndicadoresDisponiveis() {
        val d = decide(OfferData(fare = 25.0, pickupDistanceKm = 1.0, tripDistanceKm = 9.0))
        assertTrue(d.metricScores.none { it.metric == Metric.REVENUE_PER_HOUR || it.metric == Metric.PICKUP_TIME })
        assertTrue(d.isPartial)
        assertTrue(d.reasons.any { it.contains("Tempo não identificado") })
        assertFalse(d.classification == Classification.GRAY)
    }

    @Test
    fun naoUsaIndicadorIsolado_pesosAlteramResultado() {
        val offer = OfferData(14.0, 1.0, 9.0, 3.0, 12.0) // R$/km fraco (1,40), R$/h forte (56)
        val kmOnly = ScoringConfig(weights = ScoringWeights(1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
        val hourOnly = ScoringConfig(weights = ScoringWeights(0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0))
        assertEquals(Classification.RED, decide(offer, config = kmOnly).classification)
        assertEquals(Classification.GREEN, decide(offer, config = hourOnly).classification)
        val balanced = decide(offer)
        assertTrue(balanced.score!! > 0.0 && balanced.score!! < 1.0)
    }

    @Test
    fun pesosZerados_usaMediaSimples() {
        val zero = ScoringConfig(weights = ScoringWeights(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
        val d = decide(OfferData(18.50, 1.2, 9.3, 4.0, 20.0), config = zero)
        val mean = d.metricScores.map { it.score }.average()
        assertEquals(mean, d.score!!, 1e-9)
    }

    @Test
    fun valoresSaoCalculadosDinamicamente_metaAlteraClassificacao() {
        val offer = OfferData(18.50, 1.2, 9.3, 4.0, 20.0)
        val strict = Goals(minRevenuePerKm = 3.0, minRevenuePerHour = 70.0, minProfitPerKm = 2.5, minProfitPerHour = 55.0)
        assertEquals(Classification.RED, decide(offer, goals = strict).classification)
    }
}
