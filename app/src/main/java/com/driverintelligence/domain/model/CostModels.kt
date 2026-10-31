package com.driverintelligence.domain.model

enum class EnergyType(val label: String, val consumptionUnit: String, val priceUnit: String) {
    GASOLINE("Gasolina", "km/L", "R$/L"),
    ETHANOL("Etanol", "km/L", "R$/L"),
    FLEX("Flex", "km/L", "R$/L"),
    DIESEL("Diesel", "km/L", "R$/L"),
    CNG("GNV", "km/m³", "R$/m³"),
    ELECTRIC("Elétrico", "km/kWh", "R$/kWh"),
    HYBRID("Híbrido", "km/L", "R$/L"),
}

enum class CostComponent(val label: String) {
    FUEL("Combustível"),
    MAINTENANCE("Manutenção"),
    TIRES("Pneus"),
    OIL("Óleo"),
    DEPRECIATION("Depreciação"),
    OTHER("Outros custos"),
}

/** Origem de um custo por km: digitado diretamente ou calculado pelo app a partir de dados do motorista. */
enum class CostSource { NOT_SET, CONFIGURED, CALCULATED }

/**
 * Perfil de custos usado pelo motor financeiro. Todos os campos são opcionais:
 * o motorista pode começar só com consumo e preço do combustível.
 */
data class CostProfile(
    /** Consumo efetivo (km por litro, m³ ou kWh). */
    val consumptionKmPerUnit: Double? = null,
    /** Preço por litro, m³ ou kWh. */
    val energyPricePerUnit: Double? = null,
    val maintenancePerKm: Double? = null,
    val tiresPerKm: Double? = null,
    val oilPerKm: Double? = null,
    val depreciationPerKm: Double? = null,
    /** Soma dos custos personalizados por km. Opcional; ausência não torna a estimativa parcial. */
    val otherCostsPerKm: Double? = null,
    /**
     * Custo operacional por km informado como valor único. Quando presente,
     * substitui a soma dos itens (manutenção, pneus, óleo, depreciação, outros).
     */
    val operationalCostPerKmOverride: Double? = null,
    /**
     * Regra anti-duplicidade: o valor único de custo operacional JÁ inclui combustível.
     * Só tem efeito quando [operationalCostPerKmOverride] está definido — custos itemizados
     * nunca incluem combustível.
     */
    val operationalCostIncludesFuel: Boolean = false,
) {
    companion object {
        val EMPTY = CostProfile()
    }
}

/** Cenário opcional de retorno sem passageiro. Nunca tratado como distância conhecida. */
sealed interface EmptyReturnScenario {
    data object None : EmptyReturnScenario
    data class PercentOfTrip(val percent: Double) : EmptyReturnScenario
    data class FixedDistance(val km: Double) : EmptyReturnScenario
}
