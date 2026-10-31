package com.driverintelligence.domain.financial

import com.driverintelligence.domain.model.FinancialResult
import com.driverintelligence.domain.model.Goals

/**
 * Valor mínimo que a corrida deveria pagar para cumprir TODAS as metas do motorista
 * (R$/km, R$/h, lucro/km, lucro/h e lucro mínimo por corrida).
 *
 * Responde à pergunta "quanto essa corrida deveria pagar?" — útil para comparar com o valor oferecido.
 */
data class FareTarget(
    /** Valor mínimo que cumpre todas as metas aplicáveis. */
    val minimumFare: Double,
    /** Meta que define o valor mínimo (a mais exigente). */
    val bindingGoal: String,
    /** Custo estimado da corrida (ponto de equilíbrio: lucro zero). Nulo sem custos configurados. */
    val breakEven: Double?,
    /** Valor oferecido − valor mínimo (positivo = acima das metas). */
    val gap: Double?,
)

object FareAdvisor {

    fun target(result: FinancialResult, goals: Goals): FareTarget? {
        val km = result.totalDistanceKm?.takeIf { it > 0 } ?: return null
        val hours = result.totalTimeMin?.takeIf { it > 0 }?.div(60.0)
        val cost = result.costPerKm?.let { it * km }

        val candidates = buildList {
            add(goals.minRevenuePerKm * km to "valor por km")
            if (hours != null) add(goals.minRevenuePerHour * hours to "valor por hora")
            if (cost != null) {
                add(cost + goals.minProfitPerKm * km to "lucro por km")
                if (hours != null) add(cost + goals.minProfitPerHour * hours to "lucro por hora")
                goals.minProfitPerTrip?.let { add(cost + it to "lucro mínimo por corrida") }
            }
        }.filter { it.first.isFinite() && it.first > 0 }

        val binding = candidates.maxByOrNull { it.first } ?: return null
        return FareTarget(
            minimumFare = binding.first,
            bindingGoal = binding.second,
            breakEven = cost,
            gap = result.grossRevenue?.let { it - binding.first },
        )
    }
}
