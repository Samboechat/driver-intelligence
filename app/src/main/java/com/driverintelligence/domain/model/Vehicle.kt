package com.driverintelligence.domain.model

enum class ConsumptionMode(val label: String) {
    CITY("Urbano"),
    HIGHWAY("Rodoviário"),
    AVERAGE("Média urbano/rodoviário"),
    CUSTOM("Personalizado"),
}

data class CustomCost(val id: Long = 0, val label: String, val perKm: Double)

data class CostItem(val perKm: Double? = null, val source: CostSource = CostSource.NOT_SET) {
    val isSet: Boolean get() = perKm != null && source != CostSource.NOT_SET
}

data class Vehicle(
    val id: Long = 0,
    val name: String,
    val brand: String? = null,
    val model: String? = null,
    val year: Int? = null,
    val energyType: EnergyType = EnergyType.FLEX,
    val consumptionCity: Double? = null,
    val consumptionHighway: Double? = null,
    val consumptionCustom: Double? = null,
    val consumptionMode: ConsumptionMode = ConsumptionMode.CITY,
    val energyPrice: Double? = null,
    val maintenance: CostItem = CostItem(),
    val tires: CostItem = CostItem(),
    val oil: CostItem = CostItem(),
    val depreciation: CostItem = CostItem(),
    val customCosts: List<CustomCost> = emptyList(),
    val operationalCostPerKmOverride: Double? = null,
    val operationalCostIncludesFuel: Boolean = false,
    val isActive: Boolean = false,
) {
    /**
     * Consumo efetivo conforme o modo escolhido. Se o valor do modo não foi preenchido,
     * usa o primeiro disponível (personalizado → urbano → rodoviário) e informa via [consumptionFallbackUsed].
     */
    val effectiveConsumption: Double?
        get() = preferredConsumption() ?: consumptionCustom ?: consumptionCity ?: consumptionHighway

    val consumptionFallbackUsed: Boolean
        get() = preferredConsumption() == null && effectiveConsumption != null

    private fun preferredConsumption(): Double? = when (consumptionMode) {
        ConsumptionMode.CITY -> consumptionCity
        ConsumptionMode.HIGHWAY -> consumptionHighway
        ConsumptionMode.CUSTOM -> consumptionCustom
        ConsumptionMode.AVERAGE -> {
            val c = consumptionCity
            val h = consumptionHighway
            if (c != null && h != null) (c + h) / 2.0 else null
        }
    }

    val displayName: String
        get() = listOfNotNull(brand, model, year?.toString()).joinToString(" ").ifBlank { name }

    fun toCostProfile(): CostProfile = CostProfile(
        consumptionKmPerUnit = effectiveConsumption,
        energyPricePerUnit = energyPrice,
        maintenancePerKm = maintenance.perKm.takeIf { maintenance.isSet },
        tiresPerKm = tires.perKm.takeIf { tires.isSet },
        oilPerKm = oil.perKm.takeIf { oil.isSet },
        depreciationPerKm = depreciation.perKm.takeIf { depreciation.isSet },
        otherCostsPerKm = customCosts.filter { it.perKm.isFinite() && it.perKm >= 0 }
            .takeIf { it.isNotEmpty() }?.sumOf { it.perKm },
        operationalCostPerKmOverride = operationalCostPerKmOverride,
        operationalCostIncludesFuel = operationalCostIncludesFuel,
    )

    companion object {
        /** Custo por km a partir de um gasto e de uma duração em km (ex.: jogo de pneus ÷ durabilidade). */
        fun perKmFrom(totalCost: Double?, durationKm: Double?): Double? {
            if (totalCost == null || durationKm == null || durationKm <= 0 || totalCost < 0) return null
            val v = totalCost / durationKm
            return if (v.isFinite()) v else null
        }
    }
}
