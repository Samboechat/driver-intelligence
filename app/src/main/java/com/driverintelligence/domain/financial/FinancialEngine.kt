package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.CostComponent
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.EmptyReturnEstimate
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.FinancialResult
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.OfferField
import com.driverintelligence.domain.util.Br

/**
 * Motor financeiro. Puro, determinístico e independente da interface.
 *
 * Fórmulas:
 *  distância total = busca + viagem
 *  tempo total     = busca + viagem
 *  R$/km           = valor ÷ distância total
 *  R$/h            = valor ÷ (tempo total ÷ 60)
 *  combustível     = (distância total ÷ consumo) × preço
 *  custo operac.   = distância total × custo operacional por km
 *  lucro operac.   = valor − combustível − custo operacional
 *
 * Regra anti-duplicidade: se o custo operacional por km foi informado como valor único
 * marcado como "inclui combustível", o combustível é exibido mas NÃO é descontado de novo.
 */
class FinancialEngine {

    fun calculate(
        offer: OfferData,
        costs: CostProfile,
        emptyReturn: EmptyReturnScenario = EmptyReturnScenario.None,
    ): FinancialResult {
        val issues = mutableListOf<String>()
        val missingInputs = mutableSetOf<OfferField>()

        fun input(value: Double?, field: OfferField, allowZero: Boolean): Double? {
            if (value == null) {
                missingInputs += field
                return null
            }
            if (!value.isFinite() || value < 0.0 || (!allowZero && value == 0.0)) {
                issues += "Valor inválido para ${field.label}."
                missingInputs += field
                return null
            }
            return value
        }

        val fare = input(offer.fare, OfferField.FARE, allowZero = false)
        val pickupKm = input(offer.pickupDistanceKm, OfferField.PICKUP_DISTANCE, allowZero = true)
        val tripKm = input(offer.tripDistanceKm, OfferField.TRIP_DISTANCE, allowZero = false)
        val pickupMin = input(offer.pickupTimeMin, OfferField.PICKUP_TIME, allowZero = true)
        val tripMin = input(offer.tripTimeMin, OfferField.TRIP_TIME, allowZero = true)

        val totalKm = if (pickupKm != null && tripKm != null) pickupKm + tripKm else null
        val totalMin = if (pickupMin != null && tripMin != null) pickupMin + tripMin else null

        val revenuePerKm = safeDiv(fare, totalKm)
        val revenuePerHour = perHour(fare, totalMin)

        // ---- Custos por km ----
        val missingCosts = mutableSetOf<CostComponent>()

        val consumption = costs.consumptionKmPerUnit?.takeIf { it.isFinite() && it > 0.0 }
        val energyPrice = costs.energyPricePerUnit?.takeIf { it.isFinite() && it >= 0.0 }
        if (costs.consumptionKmPerUnit != null && consumption == null) issues += "Consumo do veículo inválido."
        if (costs.energyPricePerUnit != null && energyPrice == null) issues += "Preço do combustível inválido."
        val fuelPerKm = if (consumption != null && energyPrice != null) energyPrice / consumption else null

        val override = costs.operationalCostPerKmOverride?.takeIf { it.isFinite() && it >= 0.0 }
        if (costs.operationalCostPerKmOverride != null && override == null) issues += "Custo operacional por km inválido."

        val operationalPerKm: Double?
        if (override != null) {
            operationalPerKm = override
        } else {
            val itemized = listOf(
                CostComponent.MAINTENANCE to costs.maintenancePerKm,
                CostComponent.TIRES to costs.tiresPerKm,
                CostComponent.OIL to costs.oilPerKm,
                CostComponent.DEPRECIATION to costs.depreciationPerKm,
            )
            var sum = 0.0
            var any = false
            for ((component, value) in itemized) {
                val v = value?.takeIf { it.isFinite() && it >= 0.0 }
                if (v == null) missingCosts += component else {
                    sum += v
                    any = true
                }
            }
            val other = costs.otherCostsPerKm?.takeIf { it.isFinite() && it >= 0.0 }
            if (other != null) {
                sum += other
                any = true
            }
            operationalPerKm = if (any) sum else null
        }

        val fuelIncluded = costs.operationalCostIncludesFuel && override != null
        if (!fuelIncluded && fuelPerKm == null) missingCosts += CostComponent.FUEL

        val fuelCost = if (totalKm != null && fuelPerKm != null) totalKm * fuelPerKm else null
        val operationalCost = if (totalKm != null && operationalPerKm != null) totalKm * operationalPerKm else null

        val deductedFuelPerKm = if (fuelIncluded) 0.0 else fuelPerKm
        val costPerKm = when {
            deductedFuelPerKm == null && operationalPerKm == null -> null
            else -> (deductedFuelPerKm ?: 0.0) + (operationalPerKm ?: 0.0)
        }
        val totalCost = if (totalKm != null && costPerKm != null) totalKm * costPerKm else null

        val revenueAfterFuel = if (fare != null && fuelCost != null) fare - fuelCost else null
        val operatingProfit = if (fare != null && totalCost != null) fare - totalCost else null
        val profitPerKm = safeDiv(operatingProfit, totalKm)
        val profitPerHour = perHour(operatingProfit, totalMin)
        val margin = safeDiv(operatingProfit, fare)
        val productiveShare = if (tripKm != null && totalKm != null && totalKm > 0.0) tripKm / totalKm else null

        val emptyReturnEstimate = estimateEmptyReturn(emptyReturn, tripKm, costPerKm, operatingProfit)

        return FinancialResult(
            input = offer,
            totalDistanceKm = totalKm,
            totalTimeMin = totalMin,
            grossRevenue = fare,
            revenuePerKm = revenuePerKm,
            revenuePerHour = revenuePerHour,
            fuelCost = fuelCost,
            fuelIncludedInOperational = fuelIncluded,
            operationalCost = operationalCost,
            totalCost = totalCost,
            costPerKm = costPerKm,
            revenueAfterFuel = revenueAfterFuel,
            operatingProfit = operatingProfit,
            profitPerKm = profitPerKm,
            profitPerHour = profitPerHour,
            operatingMargin = margin,
            productiveDistanceShare = productiveShare,
            unproductiveDistanceKm = pickupKm,
            unproductiveTimeMin = pickupMin,
            emptyReturn = emptyReturnEstimate,
            missingInputs = missingInputs,
            missingCosts = missingCosts,
            issues = issues,
        )
    }

    private fun estimateEmptyReturn(
        scenario: EmptyReturnScenario,
        tripKm: Double?,
        costPerKm: Double?,
        operatingProfit: Double?,
    ): EmptyReturnEstimate? {
        val (distance, description) = when (scenario) {
            EmptyReturnScenario.None -> return null
            is EmptyReturnScenario.PercentOfTrip -> {
                if (tripKm == null || !scenario.percent.isFinite() || scenario.percent <= 0.0) return null
                tripKm * scenario.percent / 100.0 to
                    "Cenário: retorno vazio de ${Br.decimal(scenario.percent, 0)}% da viagem"
            }
            is EmptyReturnScenario.FixedDistance -> {
                if (!scenario.km.isFinite() || scenario.km <= 0.0) return null
                scenario.km to "Cenário: retorno vazio de ${Br.km(scenario.km)}"
            }
        }
        val cost = costPerKm?.let { distance * it }
        val profitAfter = if (operatingProfit != null && cost != null) operatingProfit - cost else null
        return EmptyReturnEstimate(distance, cost, profitAfter, description)
    }

    private fun safeDiv(numerator: Double?, denominator: Double?): Double? {
        if (numerator == null || denominator == null || denominator <= 0.0) return null
        val r = numerator / denominator
        return if (r.isFinite()) r else null
    }

    private fun perHour(amount: Double?, minutes: Double?): Double? {
        if (amount == null || minutes == null || minutes <= 0.0) return null
        val r = amount / (minutes / 60.0)
        return if (r.isFinite()) r else null
    }
}
