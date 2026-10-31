package com.driverintelligence.domain.model

/**
 * Dados de uma oferta de corrida, vindos do OCR ou de entrada manual.
 * Campo nulo significa "não identificado" — nunca é preenchido com valor presumido.
 */
data class OfferData(
    val fare: Double? = null,
    val pickupDistanceKm: Double? = null,
    val tripDistanceKm: Double? = null,
    val pickupTimeMin: Double? = null,
    val tripTimeMin: Double? = null,
    val category: String? = null,
    val origin: String? = null,
    val destination: String? = null,
    /** Valor de dinâmico/bônus exibido separadamente ("+R$ 3,00", "Inclui R$ 2,00"). */
    val surgeAmount: Double? = null,
    /** Valor por km exibido pelo próprio app, quando houver ("R$ 1,80/km"). */
    val displayedRatePerKm: Double? = null,
    val passengerRating: Double? = null,
)

enum class OfferField(val label: String) {
    FARE("valor da corrida"),
    PICKUP_DISTANCE("distância até o embarque"),
    TRIP_DISTANCE("distância da viagem"),
    PICKUP_TIME("tempo até o embarque"),
    TRIP_TIME("tempo da viagem"),
}

enum class DataSource(val label: String) { OCR("Leitura automática"), MANUAL("Entrada manual") }

/** Campos sem os quais nenhuma recomendação é emitida. */
val ESSENTIAL_FIELDS: Set<OfferField> = setOf(
    OfferField.FARE,
    OfferField.PICKUP_DISTANCE,
    OfferField.TRIP_DISTANCE,
)

fun OfferData.missingFields(): Set<OfferField> = buildSet {
    if (fare == null) add(OfferField.FARE)
    if (pickupDistanceKm == null) add(OfferField.PICKUP_DISTANCE)
    if (tripDistanceKm == null) add(OfferField.TRIP_DISTANCE)
    if (pickupTimeMin == null) add(OfferField.PICKUP_TIME)
    if (tripTimeMin == null) add(OfferField.TRIP_TIME)
}
