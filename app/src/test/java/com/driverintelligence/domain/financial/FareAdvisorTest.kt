package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.OfferData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FareAdvisorTest {

    private val fin = FinancialEngine()

    @Test
    fun valorMinimo_definidoPelaMetaMaisExigente() {
        // 10,5 km, 24 min, combustível 6,20 ÷ 11 km/L
        val r = fin.calculate(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), CostProfile(11.0, 6.2))
        val t = FareAdvisor.target(r, Goals())!!
        // Candidatos: 2,00×10,5 = 21,00 | 40×0,4 = 16,00 | custo 5,918 + 1,2×10,5 = 18,518 | 5,918 + 30×0,4 = 17,918
        assertEquals(21.0, t.minimumFare, 1e-9)
        assertEquals("valor por km", t.bindingGoal)
        assertEquals(10.5 * 6.2 / 11.0, t.breakEven!!, 1e-9)
        assertEquals(18.5 - 21.0, t.gap!!, 1e-9)
    }

    @Test
    fun lucroMinimoPorCorrida_podeSerAMetaDeterminante() {
        val r = fin.calculate(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), CostProfile(11.0, 6.2))
        val t = FareAdvisor.target(r, Goals(minProfitPerTrip = 20.0))!!
        assertEquals(10.5 * 6.2 / 11.0 + 20.0, t.minimumFare, 1e-9)
        assertEquals("lucro mínimo por corrida", t.bindingGoal)
    }

    @Test
    fun semCustosESemTempo_usaSoValorPorKm() {
        val r = fin.calculate(OfferData(fare = 18.5, pickupDistanceKm = 1.2, tripDistanceKm = 9.3), CostProfile.EMPTY)
        val t = FareAdvisor.target(r, Goals())!!
        assertEquals(21.0, t.minimumFare, 1e-9)
        assertNull(t.breakEven)
    }

    @Test
    fun semDistancia_semRecomendacao() {
        val r = fin.calculate(OfferData(fare = 18.5), CostProfile.EMPTY)
        assertNull(FareAdvisor.target(r, Goals()))
    }
}
