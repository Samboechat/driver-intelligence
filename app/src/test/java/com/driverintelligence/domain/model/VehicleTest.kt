package com.driverintelligence.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VehicleTest {

    private val base = Vehicle(name = "Onix", consumptionCity = 11.0, consumptionHighway = 14.0, energyPrice = 6.2)

    @Test
    fun consumoPorModo() {
        assertEquals(11.0, base.effectiveConsumption!!, 1e-9)
        assertEquals(14.0, base.copy(consumptionMode = ConsumptionMode.HIGHWAY).effectiveConsumption!!, 1e-9)
        assertEquals(12.5, base.copy(consumptionMode = ConsumptionMode.AVERAGE).effectiveConsumption!!, 1e-9)
        assertFalse(base.consumptionFallbackUsed)
    }

    @Test
    fun consumoComFallbackSinalizado() {
        val v = base.copy(consumptionMode = ConsumptionMode.CUSTOM)
        assertEquals(11.0, v.effectiveConsumption!!, 1e-9)
        assertTrue(v.consumptionFallbackUsed)
        assertNull(Vehicle(name = "x").effectiveConsumption)
    }

    @Test
    fun perfilDeCustos_soUsaItensConfigurados() {
        val v = base.copy(
            maintenance = CostItem(0.08, CostSource.CONFIGURED),
            tires = CostItem(0.05, CostSource.CALCULATED),
            oil = CostItem(0.02, CostSource.NOT_SET),
            customCosts = listOf(CustomCost(label = "Lavagem", perKm = 0.01), CustomCost(label = "Celular", perKm = 0.02)),
        )
        val p = v.toCostProfile()
        assertEquals(0.08, p.maintenancePerKm!!, 1e-9)
        assertEquals(0.05, p.tiresPerKm!!, 1e-9)
        assertNull(p.oilPerKm)
        assertNull(p.depreciationPerKm)
        assertEquals(0.03, p.otherCostsPerKm!!, 1e-9)
        assertEquals(11.0, p.consumptionKmPerUnit!!, 1e-9)
    }

    @Test
    fun calculadoraDeCustoPorKm() {
        assertEquals(0.05, Vehicle.perKmFrom(2000.0, 40000.0)!!, 1e-9)
        assertNull(Vehicle.perKmFrom(2000.0, 0.0))
        assertNull(Vehicle.perKmFrom(null, 100.0))
    }
}
