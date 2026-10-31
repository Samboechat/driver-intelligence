package com.driverintelligence.domain.model

enum class Classification(val label: String, val shortLabel: String) {
    GREEN("Rentável", "RENTÁVEL"),
    YELLOW("Rentabilidade moderada", "MODERADA"),
    RED("Abaixo da meta", "ABAIXO DA META"),
    GRAY("Dados insuficientes", "INCOMPLETO"),
}

/**
 * Metas e limites do motorista. Os valores padrão são apenas ponto de partida
 * e devem ser ajustados no app — não representam média de mercado.
 */
data class Goals(
    val dailyRevenue: Double? = null,
    val dailyProfit: Double? = null,
    val weeklyRevenue: Double? = null,
    val monthlyRevenue: Double? = null,
    val maxDailyHours: Double? = null,
    val minRevenuePerKm: Double = 2.0,
    val minRevenuePerHour: Double = 40.0,
    val minProfitPerKm: Double = 1.2,
    val minProfitPerHour: Double = 30.0,
    val minProfitPerTrip: Double? = null,
    val maxPickupMinutes: Double = 10.0,
    /** Parte máxima aceitável da distância total que é deslocamento sem passageiro (0..1). */
    val maxUnproductiveShare: Double = 0.35,
    /** Parte máxima aceitável do valor consumida por custos (0..1). */
    val maxCostShare: Double = 0.50,
    val maxTotalDistanceKm: Double? = null,
)

enum class Metric(val label: String, val higherIsBetter: Boolean, val weakness: String, val strength: String) {
    REVENUE_PER_KM("Valor por km", true, "valor por km abaixo da meta", "bom valor por km"),
    PROFIT_PER_KM("Lucro por km", true, "lucro por km abaixo da meta", "bom lucro por km"),
    REVENUE_PER_HOUR("Valor por hora", true, "valor por hora abaixo da meta", "bom valor por hora"),
    PROFIT_PER_HOUR("Lucro por hora", true, "lucro por hora abaixo da meta", "bom lucro por hora"),
    PICKUP_TIME("Tempo até o passageiro", false, "tempo de busca elevado", "busca rápida"),
    UNPRODUCTIVE_DISTANCE("Distância de busca", false, "distância de busca elevada", "pouca distância improdutiva"),
    COST_SHARE("Peso dos custos", false, "custo operacional alto em relação ao valor", "custos baixos em relação ao valor"),
}

/** Pesos ajustáveis do sistema de pontuação. Não precisam somar 1 — são normalizados. */
data class ScoringWeights(
    val revenuePerKm: Double = 0.25,
    val profitPerKm: Double = 0.20,
    val revenuePerHour: Double = 0.20,
    val profitPerHour: Double = 0.15,
    val pickupTime: Double = 0.10,
    val unproductiveDistance: Double = 0.05,
    val costShare: Double = 0.05,
) {
    fun weightOf(metric: Metric): Double = when (metric) {
        Metric.REVENUE_PER_KM -> revenuePerKm
        Metric.PROFIT_PER_KM -> profitPerKm
        Metric.REVENUE_PER_HOUR -> revenuePerHour
        Metric.PROFIT_PER_HOUR -> profitPerHour
        Metric.PICKUP_TIME -> pickupTime
        Metric.UNPRODUCTIVE_DISTANCE -> unproductiveDistance
        Metric.COST_SHARE -> costShare
    }
}

data class ScoringConfig(
    val weights: ScoringWeights = ScoringWeights(),
    /** Pontuação mínima (0..1) para VERDE. */
    val greenThreshold: Double = 0.70,
    /** Pontuação mínima (0..1) para AMARELO. Abaixo disso, VERMELHO. */
    val yellowThreshold: Double = 0.45,
    /** Confiança mínima do reconhecimento para emitir recomendação. */
    val minRecognitionConfidence: Double = 0.60,
)

data class MetricScore(
    val metric: Metric,
    val value: Double,
    val target: Double,
    /** 0..1; 0.7 corresponde exatamente à meta. */
    val score: Double,
    val weight: Double,
) {
    val meetsTarget: Boolean get() = score >= 0.7 - 1e-9
}

data class Decision(
    val classification: Classification,
    /** Pontuação ponderada 0..1; nula quando CINZA. */
    val score: Double?,
    /** Justificativa curta, pronta para exibir. */
    val headline: String,
    val reasons: List<String>,
    val metricScores: List<MetricScore>,
    /** Resultado calculado com dados ou custos incompletos. */
    val isPartial: Boolean,
)
