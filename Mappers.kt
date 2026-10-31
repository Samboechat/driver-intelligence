package com.driverintelligence.data.local

import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.ConsumptionMode
import com.driverintelligence.domain.model.CostItem
import com.driverintelligence.domain.model.CostSource
import com.driverintelligence.domain.model.CustomCost
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.EnergyType
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.model.Vehicle

internal inline fun <reified T : Enum<T>> enumOr(value: String?, default: T): T =
    value?.let { v -> enumValues<T>().firstOrNull { it.name == v } } ?: default

fun VehicleWithCosts.toDomain(): Vehicle = with(vehicle) {
    Vehicle(
        id = id,
        name = name,
        brand = brand,
        model = model,
        year = year,
        energyType = enumOr(energyType, EnergyType.FLEX),
        consumptionCity = consumptionCity,
        consumptionHighway = consumptionHighway,
        consumptionCustom = consumptionCustom,
        consumptionMode = enumOr(consumptionMode, ConsumptionMode.CITY),
        energyPrice = energyPrice,
        maintenance = CostItem(maintenancePerKm, enumOr(maintenanceSource, CostSource.NOT_SET)),
        tires = CostItem(tiresPerKm, enumOr(tiresSource, CostSource.NOT_SET)),
        oil = CostItem(oilPerKm, enumOr(oilSource, CostSource.NOT_SET)),
        depreciation = CostItem(depreciationPerKm, enumOr(depreciationSource, CostSource.NOT_SET)),
        customCosts = customCosts.map { CustomCost(it.id, it.label, it.perKm) },
        operationalCostPerKmOverride = operationalCostPerKmOverride,
        operationalCostIncludesFuel = operationalCostIncludesFuel,
        isActive = isActive,
    )
}

fun Vehicle.toEntity(createdAt: Long, now: Long): VehicleEntity = VehicleEntity(
    id = id,
    name = name.ifBlank { displayName },
    brand = brand,
    model = model,
    year = year,
    energyType = energyType.name,
    consumptionCity = consumptionCity,
    consumptionHighway = consumptionHighway,
    consumptionCustom = consumptionCustom,
    consumptionMode = consumptionMode.name,
    energyPrice = energyPrice,
    maintenancePerKm = maintenance.perKm,
    maintenanceSource = (if (maintenance.perKm == null) CostSource.NOT_SET else maintenance.source).name,
    tiresPerKm = tires.perKm,
    tiresSource = (if (tires.perKm == null) CostSource.NOT_SET else tires.source).name,
    oilPerKm = oil.perKm,
    oilSource = (if (oil.perKm == null) CostSource.NOT_SET else oil.source).name,
    depreciationPerKm = depreciation.perKm,
    depreciationSource = (if (depreciation.perKm == null) CostSource.NOT_SET else depreciation.source).name,
    operationalCostPerKmOverride = operationalCostPerKmOverride,
    operationalCostIncludesFuel = operationalCostIncludesFuel,
    isActive = isActive,
    createdAt = createdAt,
    updatedAt = now,
)

fun Vehicle.customCostEntities(): List<CustomCostEntity> =
    customCosts.filter { it.label.isNotBlank() }.map { CustomCostEntity(vehicleId = id, label = it.label.trim(), perKm = it.perKm) }

fun TripEntity.toDomain() = Trip(
    id = id,
    offerId = offerId,
    vehicleId = vehicleId,
    startedAt = startedAt,
    fare = fare,
    pickupKm = pickupKm,
    tripKm = tripKm,
    totalKm = totalKm,
    pickupMin = pickupMin,
    tripMin = tripMin,
    totalMin = totalMin,
    revenuePerKm = revenuePerKm,
    revenuePerHour = revenuePerHour,
    fuelCost = fuelCost,
    operationalCost = operationalCost,
    estimatedCost = estimatedCost,
    estimatedProfit = estimatedProfit,
    costPartial = costPartial,
    classification = classification?.let { enumOr(it, Classification.GRAY) },
    recognitionConfidence = recognitionConfidence,
    source = enumOr(source, DataSource.MANUAL),
    category = category,
    origin = origin,
    destination = destination,
    notes = notes,
)

fun Trip.toEntity(createdAt: Long, now: Long) = TripEntity(
    id = id,
    offerId = offerId,
    vehicleId = vehicleId,
    startedAt = startedAt,
    fare = fare,
    pickupKm = pickupKm,
    tripKm = tripKm,
    totalKm = totalKm,
    pickupMin = pickupMin,
    tripMin = tripMin,
    totalMin = totalMin,
    revenuePerKm = revenuePerKm,
    revenuePerHour = revenuePerHour,
    fuelCost = fuelCost,
    operationalCost = operationalCost,
    estimatedCost = estimatedCost,
    estimatedProfit = estimatedProfit,
    costPartial = costPartial,
    classification = classification?.name,
    recognitionConfidence = recognitionConfidence,
    source = source.name,
    category = category,
    origin = origin,
    destination = destination,
    notes = notes,
    createdAt = createdAt,
    updatedAt = now,
)

fun AnalyzedOfferEntity.toDomain() = AnalyzedOffer(
    id = id,
    fingerprint = fingerprint,
    detectedAt = detectedAt,
    vehicleId = vehicleId,
    fare = fare,
    pickupKm = pickupKm,
    tripKm = tripKm,
    totalKm = totalKm,
    pickupMin = pickupMin,
    tripMin = tripMin,
    totalMin = totalMin,
    revenuePerKm = revenuePerKm,
    revenuePerHour = revenuePerHour,
    estimatedCost = estimatedCost,
    estimatedProfit = estimatedProfit,
    profitPerKm = profitPerKm,
    profitPerHour = profitPerHour,
    costPartial = costPartial,
    classification = enumOr(classification, Classification.GRAY),
    score = score,
    headline = headline,
    confidence = confidence,
    source = enumOr(source, DataSource.OCR),
    category = category,
    origin = origin,
    destination = destination,
    surge = surge,
    registeredTripId = registeredTripId,
)

fun AnalyzedOffer.toEntity() = AnalyzedOfferEntity(
    id = id,
    fingerprint = fingerprint,
    detectedAt = detectedAt,
    vehicleId = vehicleId,
    fare = fare,
    pickupKm = pickupKm,
    tripKm = tripKm,
    totalKm = totalKm,
    pickupMin = pickupMin,
    tripMin = tripMin,
    totalMin = totalMin,
    revenuePerKm = revenuePerKm,
    revenuePerHour = revenuePerHour,
    estimatedCost = estimatedCost,
    estimatedProfit = estimatedProfit,
    profitPerKm = profitPerKm,
    profitPerHour = profitPerHour,
    costPartial = costPartial,
    classification = classification.name,
    score = score,
    headline = headline,
    confidence = confidence,
    source = source.name,
    category = category,
    origin = origin,
    destination = destination,
    surge = surge,
    registeredTripId = registeredTripId,
)
