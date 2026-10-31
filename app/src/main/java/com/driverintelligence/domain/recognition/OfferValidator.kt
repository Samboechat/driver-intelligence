package com.driverintelligence.domain.recognition

import com.driverintelligence.domain.model.ESSENTIAL_FIELDS
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.OfferField
import com.driverintelligence.domain.model.missingFields

enum class ValidationStatus { VALID, INCOMPLETE, INVALID }

enum class IssueSeverity { WARNING, ERROR }

data class ValidationIssue(val field: OfferField?, val message: String, val severity: IssueSeverity)

data class ValidationResult(
    val status: ValidationStatus,
    val issues: List<ValidationIssue>,
    /** Fator 0..1 aplicado à confiança da leitura. */
    val confidenceFactor: Double,
)

/**
 * Validação de plausibilidade. Não "corrige" valores: apenas sinaliza e reduz a confiança,
 * para que dados suspeitos nunca gerem recomendação definitiva.
 */
class OfferValidator(private val limits: Limits = Limits()) {

    data class Limits(
        val fare: ClosedFloatingPointRange<Double> = 3.0..1500.0,
        val pickupKm: ClosedFloatingPointRange<Double> = 0.0..40.0,
        val tripKm: ClosedFloatingPointRange<Double> = 0.2..400.0,
        val pickupMin: ClosedFloatingPointRange<Double> = 0.0..90.0,
        val tripMin: ClosedFloatingPointRange<Double> = 1.0..600.0,
        /** Velocidade média plausível em km/h. */
        val speed: ClosedFloatingPointRange<Double> = 2.0..140.0,
        val revenuePerKm: ClosedFloatingPointRange<Double> = 0.3..25.0,
    )

    fun validate(offer: OfferData): ValidationResult {
        val issues = mutableListOf<ValidationIssue>()

        fun range(value: Double?, r: ClosedFloatingPointRange<Double>, field: OfferField) {
            if (value != null && (!value.isFinite() || value !in r)) {
                issues += ValidationIssue(field, "Valor fora do esperado para ${field.label}.", IssueSeverity.ERROR)
            }
        }
        range(offer.fare, limits.fare, OfferField.FARE)
        range(offer.pickupDistanceKm, limits.pickupKm, OfferField.PICKUP_DISTANCE)
        range(offer.tripDistanceKm, limits.tripKm, OfferField.TRIP_DISTANCE)
        range(offer.pickupTimeMin, limits.pickupMin, OfferField.PICKUP_TIME)
        range(offer.tripTimeMin, limits.tripMin, OfferField.TRIP_TIME)

        val tripKm = offer.tripDistanceKm
        val tripMin = offer.tripTimeMin
        if (tripKm != null && tripMin != null && tripMin > 0) {
            val speed = tripKm / (tripMin / 60.0)
            if (speed !in limits.speed) {
                issues += ValidationIssue(OfferField.TRIP_TIME, "Tempo e distância da viagem incoerentes.", IssueSeverity.WARNING)
            }
        }
        val pickupKm = offer.pickupDistanceKm
        val pickupMin = offer.pickupTimeMin
        if (pickupKm != null && pickupMin != null && pickupMin > 0 && pickupKm > 0) {
            val speed = pickupKm / (pickupMin / 60.0)
            if (speed > limits.speed.endInclusive) {
                issues += ValidationIssue(OfferField.PICKUP_TIME, "Tempo e distância de busca incoerentes.", IssueSeverity.WARNING)
            }
        }
        val fare = offer.fare
        if (fare != null && pickupKm != null && tripKm != null && pickupKm + tripKm > 0) {
            val rpk = fare / (pickupKm + tripKm)
            if (rpk !in limits.revenuePerKm) {
                issues += ValidationIssue(OfferField.FARE, "Valor por km improvável — confira a leitura.", IssueSeverity.WARNING)
            }
        }

        val missing = offer.missingFields()
        val missingEssential: Set<OfferField?> = missing.filter { it in ESSENTIAL_FIELDS }.toSet()
        missing.forEach { field ->
            issues += ValidationIssue(
                field,
                "Não identificado: ${field.label}.",
                if (field in ESSENTIAL_FIELDS) IssueSeverity.ERROR else IssueSeverity.WARNING,
            )
        }

        val errors = issues.count { it.severity == IssueSeverity.ERROR && it.field !in missingEssential }
        val warnings = issues.count { it.severity == IssueSeverity.WARNING && it.message.startsWith("Não identificado").not() }
        val status = when {
            errors > 0 -> ValidationStatus.INVALID
            missingEssential.isNotEmpty() -> ValidationStatus.INCOMPLETE
            else -> ValidationStatus.VALID
        }
        var factor = 1.0
        factor *= Math.pow(0.5, errors.toDouble())
        factor *= Math.pow(0.8, warnings.toDouble())
        return ValidationResult(status, issues, factor.coerceIn(0.0, 1.0))
    }
}
