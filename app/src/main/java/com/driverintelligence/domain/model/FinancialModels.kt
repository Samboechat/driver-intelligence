package com.driverintelligence.domain.model

/**
 * Resultado do motor financeiro. Terminologia (nunca misturar):
 *  - grossRevenue: faturamento bruto = valor oferecido ao motorista.
 *  - revenueAfterFuel: faturamento − combustível.
 *  - operatingProfit: faturamento − combustível − custos operacionais por km (estimado).
 *  - Lucro líquido NÃO é calculado por corrida: exige custos fixos (seguro, IPVA, financiamento,
 *    celular) e impostos, que não são proporcionais a uma corrida.
 */
data class FinancialResult(
    val input: OfferData,
    val totalDistanceKm: Double?,
    val totalTimeMin: Double?,
    val grossRevenue: Double?,
    val revenuePerKm: Double?,
    val revenuePerHour: Double?,
    /** Custo de combustível estimado. Mostrado mesmo quando incluído no custo operacional. */
    val fuelCost: Double?,
    /** true quando o combustível já está dentro do custo operacional e não é descontado em separado. */
    val fuelIncludedInOperational: Boolean,
    val operationalCost: Double?,
    /** Soma dos custos efetivamente descontados do faturamento. */
    val totalCost: Double?,
    val costPerKm: Double?,
    val revenueAfterFuel: Double?,
    val operatingProfit: Double?,
    val profitPerKm: Double?,
    val profitPerHour: Double?,
    /** Margem operacional (0..1). */
    val operatingMargin: Double?,
    /** Eficiência da corrida: parte da distância total que é remunerada (viagem ÷ total). */
    val productiveDistanceShare: Double?,
    /** Distância improdutiva de busca (até o passageiro). */
    val unproductiveDistanceKm: Double?,
    /** Tempo improdutivo de busca. */
    val unproductiveTimeMin: Double?,
    val emptyReturn: EmptyReturnEstimate?,
    val missingInputs: Set<OfferField>,
    /** Componentes de custo não configurados — se não vazio, lucro é estimativa parcial. */
    val missingCosts: Set<CostComponent>,
    val issues: List<String>,
) {
    val hasEssentials: Boolean get() = missingInputs.none { it in ESSENTIAL_FIELDS }
    val isCostEstimatePartial: Boolean get() = missingCosts.isNotEmpty()
}

data class EmptyReturnEstimate(
    val distanceKm: Double,
    /** Nulo quando não há nenhum custo por km configurado. */
    val cost: Double?,
    val profitAfterReturn: Double?,
    val description: String,
)
