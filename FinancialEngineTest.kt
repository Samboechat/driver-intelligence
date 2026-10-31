package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.CostComponent
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.OfferField
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FinancialEngineTest {

    private val engine = FinancialEngine()
    private val eps = 1e-6

    private val fullCosts = CostProfile(
        consumptionKmPerUnit = 12.0,
        energyPricePerUnit = 6.29,
        maintenancePerKm = 0.08,
        tiresPerKm = 0.05,
        oilPerKm = 0.02,
        depreciationPerKm = 0.12,
    )

    @Test
    fun exemploDaEspecificacao_rsPorKmERsPorHora() {
        val r = engine.calculate(OfferData(18.50, 1.2, 9.3, 4.0, 20.0), CostProfile.EMPTY)
        assertEquals(10.5, r.totalDistanceKm!!, eps)
        assertEquals(24.0, r.totalTimeMin!!, eps)
        assertEquals(18.50 / 10.5, r.revenuePerKm!!, eps) // 1,7619 → "R$ 1,76/km"
        assertEquals(46.25, r.revenuePerHour!!, eps)
    }

    @Test
    fun corridaCurta_comCustoParcial() {
        val costs = CostProfile(consumptionKmPerUnit = 10.0, energyPricePerUnit = 6.0, maintenancePerKm = 0.10)
        val r = engine.calculate(OfferData(8.0, 0.8, 2.5, 3.0, 8.0), costs)
        assertEquals(3.3, r.totalDistanceKm!!, eps)
        assertEquals(11.0, r.totalTimeMin!!, eps)
        assertEquals(8.0 / 3.3, r.revenuePerKm!!, eps)
        assertEquals(8.0 / (11.0 / 60.0), r.revenuePerHour!!, eps)
        assertEquals(1.98, r.fuelCost!!, eps)
        assertEquals(0.33, r.operationalCost!!, eps)
        assertEquals(8.0 - 1.98 - 0.33, r.operatingProfit!!, eps)
        assertEquals(8.0 - 1.98, r.revenueAfterFuel!!, eps)
        assertTrue(r.isCostEstimatePartial)
        assertEquals(setOf(CostComponent.TIRES, CostComponent.OIL, CostComponent.DEPRECIATION), r.missingCosts)
    }

    @Test
    fun corridaLonga_comTodosOsCustos() {
        val r = engine.calculate(OfferData(95.0, 3.0, 60.0, 7.0, 55.0), fullCosts)
        assertEquals(63.0, r.totalDistanceKm!!, eps)
        assertEquals(63.0 / 12.0 * 6.29, r.fuelCost!!, eps)
        assertEquals(63.0 * 0.27, r.operationalCost!!, eps)
        val profit = 95.0 - 63.0 / 12.0 * 6.29 - 63.0 * 0.27
        assertEquals(profit, r.operatingProfit!!, eps)
        assertEquals(profit / 63.0, r.profitPerKm!!, eps)
        assertEquals(profit / (62.0 / 60.0), r.profitPerHour!!, eps)
        assertEquals(profit / 95.0, r.operatingMargin!!, eps)
        assertEquals(60.0 / 63.0, r.productiveDistanceShare!!, eps)
        assertEquals(3.0, r.unproductiveDistanceKm!!, eps)
        assertEquals(7.0, r.unproductiveTimeMin!!, eps)
        assertFalse(r.isCostEstimatePartial)
        assertTrue(r.issues.isEmpty())
    }

    @Test
    fun valorBaixo_geraPrejuizo() {
        val r = engine.calculate(OfferData(5.5, 4.0, 1.5, 10.0, 5.0), fullCosts)
        val cost = 5.5 * (6.29 / 12.0 + 0.27)
        assertEquals(5.5 - cost, r.operatingProfit!!, eps)
        assertTrue(r.operatingProfit!! > 0) // ainda positivo, mas margem pequena
        assertEquals(4.0 / 5.5, 1 - r.productiveDistanceShare!!, eps)
    }

    @Test
    fun distanciaDeBuscaElevada_reduzEficiencia() {
        val r = engine.calculate(OfferData(20.0, 9.0, 6.0, 18.0, 12.0), fullCosts)
        assertEquals(15.0, r.totalDistanceKm!!, eps)
        assertEquals(0.4, r.productiveDistanceShare!!, eps)
        assertEquals(9.0, r.unproductiveDistanceKm!!, eps)
    }

    @Test
    fun tempoElevado_reduzValorPorHora() {
        val r = engine.calculate(OfferData(30.0, 1.0, 10.0, 5.0, 85.0), CostProfile.EMPTY)
        assertEquals(20.0, r.revenuePerHour!!, eps)
    }

    @Test
    fun combustivelCaro() {
        val cheap = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), CostProfile(10.0, 5.0))
        val expensive = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), CostProfile(10.0, 8.5))
        assertEquals(5.0, cheap.fuelCost!!, eps)
        assertEquals(8.5, expensive.fuelCost!!, eps)
        assertEquals(cheap.operatingProfit!! - 3.5, expensive.operatingProfit!!, eps)
    }

    @Test
    fun custoOperacionalUnico_incluindoCombustivel_naoDescontaDuasVezes() {
        val costs = CostProfile(consumptionKmPerUnit = 10.0, energyPricePerUnit = 6.0, operationalCostPerKmOverride = 0.9, operationalCostIncludesFuel = true)
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), costs)
        assertTrue(r.fuelIncludedInOperational)
        assertEquals(6.0, r.fuelCost!!, eps) // exibido apenas como informação
        assertEquals(9.0, r.operationalCost!!, eps)
        assertEquals(9.0, r.totalCost!!, eps)
        assertEquals(11.0, r.operatingProfit!!, eps)
        assertFalse(CostComponent.FUEL in r.missingCosts)
    }

    @Test
    fun custoOperacionalUnico_semCombustivel_somaOsDois() {
        val costs = CostProfile(consumptionKmPerUnit = 10.0, energyPricePerUnit = 6.0, operationalCostPerKmOverride = 0.3)
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), costs)
        assertFalse(r.fuelIncludedInOperational)
        assertEquals(6.0 + 3.0, r.totalCost!!, eps)
        assertEquals(11.0, r.operatingProfit!!, eps)
        assertTrue(r.missingCosts.isEmpty())
    }

    @Test
    fun flagIncluiCombustivel_ignoradaSemValorUnico() {
        val costs = CostProfile(consumptionKmPerUnit = 10.0, energyPricePerUnit = 6.0, maintenancePerKm = 0.1, operationalCostIncludesFuel = true)
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), costs)
        assertFalse(r.fuelIncludedInOperational)
        assertEquals(6.0 + 1.0, r.totalCost!!, eps)
    }

    @Test
    fun custosPersonalizadosSomamAoOperacional() {
        val costs = fullCosts.copy(otherCostsPerKm = 0.03)
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), costs)
        assertEquals(10.0 * 0.30, r.operationalCost!!, eps)
    }

    @Test
    fun dadosIncompletos_semDistanciaDeBusca() {
        val r = engine.calculate(OfferData(fare = 18.5, tripDistanceKm = 9.3, tripTimeMin = 20.0), fullCosts)
        assertNull(r.totalDistanceKm)
        assertNull(r.revenuePerKm)
        assertNull(r.revenuePerHour)
        assertNull(r.operatingProfit)
        assertFalse(r.hasEssentials)
        assertTrue(OfferField.PICKUP_DISTANCE in r.missingInputs)
        assertTrue(OfferField.PICKUP_TIME in r.missingInputs)
    }

    @Test
    fun semTempos_calculaPorKmMasNaoPorHora() {
        val r = engine.calculate(OfferData(fare = 18.5, pickupDistanceKm = 1.2, tripDistanceKm = 9.3), fullCosts)
        assertNotNull(r.revenuePerKm)
        assertNull(r.revenuePerHour)
        assertNull(r.profitPerHour)
        assertTrue(r.hasEssentials)
    }

    @Test
    fun divisaoPorZero_temposZerados() {
        val r = engine.calculate(OfferData(10.0, 0.0, 3.0, 0.0, 0.0), CostProfile.EMPTY)
        assertEquals(3.0, r.totalDistanceKm!!, eps)
        assertEquals(0.0, r.totalTimeMin!!, eps)
        assertNull(r.revenuePerHour)
        assertEquals(10.0 / 3.0, r.revenuePerKm!!, eps)
        assertEquals(1.0, r.productiveDistanceShare!!, eps)
    }

    @Test
    fun divisaoPorZero_distanciaDaViagemZeroEhInvalida() {
        val r = engine.calculate(OfferData(10.0, 0.0, 0.0, 2.0, 3.0), CostProfile.EMPTY)
        assertNull(r.totalDistanceKm)
        assertNull(r.revenuePerKm)
        assertTrue(r.issues.isNotEmpty())
    }

    @Test
    fun consumoZero_naoGeraInfinito() {
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), CostProfile(consumptionKmPerUnit = 0.0, energyPricePerUnit = 6.0))
        assertNull(r.fuelCost)
        assertTrue(CostComponent.FUEL in r.missingCosts)
        assertTrue(r.issues.any { it.contains("Consumo") })
    }

    @Test
    fun valoresInvalidos_saoRejeitados() {
        val r = engine.calculate(OfferData(-5.0, Double.NaN, Double.POSITIVE_INFINITY, -1.0, 10.0), CostProfile.EMPTY)
        assertNull(r.grossRevenue)
        assertNull(r.totalDistanceKm)
        assertNull(r.totalTimeMin)
        assertTrue(r.issues.size >= 4)
        assertFalse(r.hasEssentials)
    }

    @Test
    fun semCustosConfigurados_lucroIndisponivel() {
        val r = engine.calculate(OfferData(20.0, 1.0, 9.0, 4.0, 16.0), CostProfile.EMPTY)
        assertNull(r.operatingProfit)
        assertNull(r.totalCost)
        assertTrue(CostComponent.FUEL in r.missingCosts)
        assertTrue(r.isCostEstimatePartial)
    }

    @Test
    fun retornoVazio_percentualDaViagem() {
        val costs = CostProfile(consumptionKmPerUnit = 10.0, energyPricePerUnit = 6.0, operationalCostPerKmOverride = 0.2)
        val r = engine.calculate(OfferData(30.0, 1.0, 10.0, 4.0, 20.0), costs, EmptyReturnScenario.PercentOfTrip(50.0))
        val er = r.emptyReturn!!
        assertEquals(5.0, er.distanceKm, eps)
        assertEquals(5.0 * 0.8, er.cost!!, eps)
        assertEquals(r.operatingProfit!! - 4.0, er.profitAfterReturn!!, eps)
        // O retorno é cenário separado: não altera o lucro da corrida.
        assertEquals(30.0 - 11.0 * 0.8, r.operatingProfit!!, eps)
    }

    @Test
    fun retornoVazio_distanciaFixa_eSemCustos() {
        val r1 = engine.calculate(OfferData(30.0, 1.0, 10.0, 4.0, 20.0), CostProfile(10.0, 6.0), EmptyReturnScenario.FixedDistance(8.0))
        assertEquals(8.0, r1.emptyReturn!!.distanceKm, eps)
        assertEquals(4.8, r1.emptyReturn!!.cost!!, eps)

        val r2 = engine.calculate(OfferData(30.0, 1.0, 10.0, 4.0, 20.0), CostProfile.EMPTY, EmptyReturnScenario.FixedDistance(8.0))
        assertNull(r2.emptyReturn!!.cost)
        assertNull(r2.emptyReturn!!.profitAfterReturn)

        val r3 = engine.calculate(OfferData(30.0, 1.0, 10.0, 4.0, 20.0), CostProfile(10.0, 6.0), EmptyReturnScenario.None)
        assertNull(r3.emptyReturn)

        val r4 = engine.calculate(OfferData(30.0, 1.0, 10.0, 4.0, 20.0), CostProfile(10.0, 6.0), EmptyReturnScenario.PercentOfTrip(-10.0))
        assertNull(r4.emptyReturn)
    }
}
