package com.driverintelligence.domain.model

import com.driverintelligence.domain.analytics.TripRecord
import com.driverintelligence.domain.financial.DecisionEngine
import com.driverintelligence.domain.financial.FinancialEngine
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OfferAnalysis

/** Corrida efetivamente REALIZADA — só criada por ação do motorista. */
data class Trip(
    val id: Long = 0,
    val offerId: Long? = null,
    val vehicleId: Long? = null,
    val startedAt: Long,
    val fare: Double,
    val pickupKm: Double? = null,
    val tripKm: Double? = null,
    val totalKm: Double? = null,
    val pickupMin: Double? = null,
    val tripMin: Double? = null,
    val totalMin: Double? = null,
    val revenuePerKm: Double? = null,
    val revenuePerHour: Double? = null,
    val fuelCost: Double? = null,
    val operationalCost: Double? = null,
    val estimatedCost: Double? = null,
    val estimatedProfit: Double? = null,
    val costPartial: Boolean = true,
    val classification: Classification? = null,
    val recognitionConfidence: Double? = null,
    val source: DataSource = DataSource.MANUAL,
    val category: String? = null,
    val origin: String? = null,
    val destination: String? = null,
    val notes: String? = null,
) {
    fun toOfferData() = OfferData(fare, pickupKm, tripKm, pickupMin, tripMin, category, origin, destination)

    fun toRecord() = TripRecord(id, startedAt, fare, totalKm, totalMin, fuelCost, operationalCost, estimatedProfit, classification)

    /** Recalcula os indicadores com os dados (possivelmente editados) e os custos atuais. */
    fun recalculated(ctx: AnalysisContext, financial: FinancialEngine = FinancialEngine(), decision: DecisionEngine = DecisionEngine()): Trip {
        val fin = financial.calculate(toOfferData(), ctx.costs)
        val dec = decision.decide(fin, ctx.goals, ctx.scoring)
        return copy(
            totalKm = fin.totalDistanceKm,
            totalMin = fin.totalTimeMin,
            revenuePerKm = fin.revenuePerKm,
            revenuePerHour = fin.revenuePerHour,
            fuelCost = fin.fuelCost,
            operationalCost = fin.operationalCost,
            estimatedCost = fin.totalCost,
            estimatedProfit = fin.operatingProfit,
            costPartial = fin.isCostEstimatePartial,
            classification = dec.classification,
        )
    }

    companion object {
        fun fromAnalysis(a: OfferAnalysis, startedAt: Long, vehicleId: Long?, offerId: Long? = null): Trip {
            val f = a.financial
            return Trip(
                offerId = offerId,
                vehicleId = vehicleId,
                startedAt = startedAt,
                fare = a.offer.fare ?: 0.0,
                pickupKm = a.offer.pickupDistanceKm,
                tripKm = a.offer.tripDistanceKm,
                totalKm = f.totalDistanceKm,
                pickupMin = a.offer.pickupTimeMin,
                tripMin = a.offer.tripTimeMin,
                totalMin = f.totalTimeMin,
                revenuePerKm = f.revenuePerKm,
                revenuePerHour = f.revenuePerHour,
                fuelCost = f.fuelCost,
                operationalCost = f.operationalCost,
                estimatedCost = f.totalCost,
                estimatedProfit = f.operatingProfit,
                costPartial = f.isCostEstimatePartial,
                classification = a.decision.classification,
                recognitionConfidence = if (a.source == DataSource.OCR) a.confidence else null,
                source = a.source,
                category = a.offer.category,
                origin = a.offer.origin,
                destination = a.offer.destination,
            )
        }
    }
}

/** Oferta ANALISADA — vista na tela, não necessariamente aceita. */
data class AnalyzedOffer(
    val id: Long = 0,
    val fingerprint: String?,
    val detectedAt: Long,
    val vehicleId: Long?,
    val fare: Double?,
    val pickupKm: Double?,
    val tripKm: Double?,
    val totalKm: Double?,
    val pickupMin: Double?,
    val tripMin: Double?,
    val totalMin: Double?,
    val revenuePerKm: Double?,
    val revenuePerHour: Double?,
    val estimatedCost: Double?,
    val estimatedProfit: Double?,
    val profitPerKm: Double?,
    val profitPerHour: Double?,
    val costPartial: Boolean,
    val classification: Classification,
    val score: Double?,
    val headline: String,
    val confidence: Double,
    val source: DataSource,
    val category: String?,
    val origin: String?,
    val destination: String?,
    val surge: Double?,
    val registeredTripId: Long? = null,
) {
    val isRegistered: Boolean get() = registeredTripId != null

    fun toOfferData() = OfferData(fare, pickupKm, tripKm, pickupMin, tripMin, category, origin, destination, surge)

    companion object {
        fun from(a: OfferAnalysis, detectedAt: Long, vehicleId: Long?): AnalyzedOffer {
            val f = a.financial
            return AnalyzedOffer(
                fingerprint = a.fingerprint,
                detectedAt = detectedAt,
                vehicleId = vehicleId,
                fare = a.offer.fare,
                pickupKm = a.offer.pickupDistanceKm,
                tripKm = a.offer.tripDistanceKm,
                totalKm = f.totalDistanceKm,
                pickupMin = a.offer.pickupTimeMin,
                tripMin = a.offer.tripTimeMin,
                totalMin = f.totalTimeMin,
                revenuePerKm = f.revenuePerKm,
                revenuePerHour = f.revenuePerHour,
                estimatedCost = f.totalCost,
                estimatedProfit = f.operatingProfit,
                profitPerKm = f.profitPerKm,
                profitPerHour = f.profitPerHour,
                costPartial = f.isCostEstimatePartial,
                classification = a.decision.classification,
                score = a.decision.score,
                headline = a.decision.headline,
                confidence = a.confidence,
                source = a.source,
                category = a.offer.category,
                origin = a.offer.origin,
                destination = a.offer.destination,
                surge = a.offer.surgeAmount,
            )
        }
    }
}
