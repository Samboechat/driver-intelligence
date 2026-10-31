package com.driverintelligence.domain.recognition

import com.driverintelligence.domain.financial.DecisionEngine
import com.driverintelligence.domain.financial.FareAdvisor
import com.driverintelligence.domain.financial.FareTarget
import com.driverintelligence.domain.financial.FinancialEngine
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.Decision
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.FinancialResult
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.ScoringConfig
import kotlin.math.roundToLong

/** Parâmetros do motorista usados em cada análise. */
data class AnalysisContext(
    val costs: CostProfile = CostProfile.EMPTY,
    val goals: Goals = Goals(),
    val scoring: ScoringConfig = ScoringConfig(),
    val emptyReturn: EmptyReturnScenario = EmptyReturnScenario.None,
    val vehicleId: Long? = null,
)

data class OfferAnalysis(
    val offer: OfferData,
    val source: DataSource,
    val parse: ParseResult?,
    val validation: ValidationResult,
    val financial: FinancialResult,
    val decision: Decision,
    /** Confiança final 0..1 (leitura × validação). 1.0 para entrada manual válida. */
    val confidence: Double,
    /** Identificador estável da oferta, ou nulo quando dados essenciais faltam. */
    val fingerprint: String?,
    /** Valor mínimo que cumpriria todas as metas do motorista. */
    val fareTarget: FareTarget? = null,
)

data class FrameAnalysis(
    val isOfferScreen: Boolean,
    val analysis: OfferAnalysis?,
)

/** Fluxo puro: texto → extração → validação → cálculo → classificação. */
class OfferAnalyzer(
    private val parser: OfferTextParser = OfferTextParser(),
    private val validator: OfferValidator = OfferValidator(),
    private val financial: FinancialEngine = FinancialEngine(),
    private val decision: DecisionEngine = DecisionEngine(),
) {

    fun analyzeFrame(frame: OcrFrame, ctx: AnalysisContext): FrameAnalysis {
        val parse = parser.parse(frame)
        if (!parse.isOfferScreen) return FrameAnalysis(isOfferScreen = false, analysis = null)
        return FrameAnalysis(isOfferScreen = true, analysis = analyze(parse.offer, DataSource.OCR, parse, ctx))
    }

    fun analyzeManual(offer: OfferData, ctx: AnalysisContext): OfferAnalysis =
        analyze(offer, DataSource.MANUAL, null, ctx)

    private fun analyze(offer: OfferData, source: DataSource, parse: ParseResult?, ctx: AnalysisContext): OfferAnalysis {
        val validation = validator.validate(offer)
        val fin = financial.calculate(offer, ctx.costs, ctx.emptyReturn)
        val confidence = when (source) {
            DataSource.MANUAL -> validation.confidenceFactor.coerceAtLeast(if (validation.status == ValidationStatus.INVALID) 0.0 else 0.9)
            DataSource.OCR -> (parse?.confidence ?: 0.0) * validation.confidenceFactor
        }
        val dec = if (validation.status == ValidationStatus.INVALID) {
            decision.decide(fin, ctx.goals, ctx.scoring, recognitionConfidence = 0.0).copy(
                headline = "Leitura inconsistente. Confira os valores na tela.",
                reasons = validation.issues.map { it.message },
            )
        } else {
            decision.decide(fin, ctx.goals, ctx.scoring, recognitionConfidence = if (source == DataSource.OCR) confidence else null)
        }
        return OfferAnalysis(
            offer = offer,
            source = source,
            parse = parse,
            validation = validation,
            financial = fin,
            decision = dec,
            confidence = confidence,
            fingerprint = fingerprint(offer),
            fareTarget = if (validation.status == ValidationStatus.INVALID) null else FareAdvisor.target(fin, ctx.goals),
        )
    }

    companion object {
        /**
         * Identificação única da oferta: valores arredondados (centavos, 100 m, minuto).
         * Pequenas variações de OCR no endereço não mudam a identidade da oferta.
         */
        fun fingerprint(offer: OfferData): String? {
            val fare = offer.fare ?: return null
            val trip = offer.tripDistanceKm ?: return null
            val pickup = offer.pickupDistanceKm ?: return null
            val cents = (fare * 100).roundToLong()
            val tripHm = (trip * 10).roundToLong()
            val pickupHm = (pickup * 10).roundToLong()
            val tripMin = offer.tripTimeMin?.roundToLong()?.toString() ?: "?"
            return "$cents|$pickupHm|$tripHm|$tripMin"
        }
    }
}
