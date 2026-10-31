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
import com.driverintelligence.domain.analytics.OfferBenchmark
import com.driverintelligence.domain.analytics.TimeCalibration
import com.driverintelligence.domain.analytics.TimeFactors
import java.time.LocalTime
import kotlin.math.roundToLong

/** Parâmetros do motorista usados em cada análise. */
data class AnalysisContext(
    val costs: CostProfile = CostProfile.EMPTY,
    val goals: Goals = Goals(),
    val scoring: ScoringConfig = ScoringConfig(),
    val emptyReturn: EmptyReturnScenario = EmptyReturnScenario.None,
    val vehicleId: Long? = null,
    /** Aprendizado de quanto os tempos da oferta atrasam na prática. */
    val calibration: TimeCalibration? = null,
    /** Ofertas recebidas antes, para comparar esta com o histórico. */
    val benchmark: OfferBenchmark? = null,
    /** Classificar com o tempo realista (corrigido) em vez do tempo exibido pelo app. */
    val useRealisticTime: Boolean = true,
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
    /** Mesma conta com os tempos corrigidos pelo aprendizado (null sem tempos ou sem calibração). */
    val realistic: FinancialResult? = null,
    val timeFactors: TimeFactors? = null,
    /** Fração das ofertas anteriores com R$/km menor que esta (0..1). */
    val percentile: Double? = null,
    val benchmarkSize: Int = 0,
    /** A classificação usou os tempos realistas. */
    val usedRealistic: Boolean = false,
) {
    /** Resultado usado na classificação: realista quando disponível e habilitado. */
    val basis: FinancialResult get() = realistic?.takeIf { usedRealistic } ?: financial
}

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
    private val hourNow: () -> Int = { LocalTime.now().hour },
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
        val factors = ctx.calibration?.factorsAt(hourNow())
        val pickupMin = offer.pickupTimeMin
        val tripMin = offer.tripTimeMin
        val finReal = if (factors != null && pickupMin != null && tripMin != null) {
            financial.calculate(offer.copy(pickupTimeMin = pickupMin * factors.pickup, tripTimeMin = tripMin * factors.trip), ctx.costs, ctx.emptyReturn)
        } else null
        val useReal = ctx.useRealisticTime && finReal != null
        val basis = if (useReal) finReal!! else fin
        val dec = if (validation.status == ValidationStatus.INVALID) {
            decision.decide(fin, ctx.goals, ctx.scoring, recognitionConfidence = 0.0).copy(
                headline = "Leitura inconsistente. Confira os valores na tela.",
                reasons = validation.issues.map { it.message },
            )
        } else {
            decision.decide(basis, ctx.goals, ctx.scoring, recognitionConfidence = if (source == DataSource.OCR) confidence else null)
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
            fareTarget = if (validation.status == ValidationStatus.INVALID) null else FareAdvisor.target(basis, ctx.goals),
            realistic = finReal,
            timeFactors = factors.takeIf { finReal != null },
            percentile = ctx.benchmark?.percentile(fin.revenuePerKm),
            benchmarkSize = ctx.benchmark?.size ?: 0,
            usedRealistic = useReal,
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
