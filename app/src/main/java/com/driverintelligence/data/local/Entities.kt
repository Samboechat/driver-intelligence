package com.driverintelligence.data.local

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Relation

@Entity(tableName = "vehicles")
data class VehicleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val brand: String?,
    val model: String?,
    val year: Int?,
    val energyType: String,
    val consumptionCity: Double?,
    val consumptionHighway: Double?,
    val consumptionCustom: Double?,
    val consumptionMode: String,
    val energyPrice: Double?,
    val maintenancePerKm: Double?,
    val maintenanceSource: String,
    val tiresPerKm: Double?,
    val tiresSource: String,
    val oilPerKm: Double?,
    val oilSource: String,
    val depreciationPerKm: Double?,
    val depreciationSource: String,
    val operationalCostPerKmOverride: Double?,
    val operationalCostIncludesFuel: Boolean,
    val isActive: Boolean,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(
    tableName = "vehicle_custom_costs",
    foreignKeys = [
        ForeignKey(
            entity = VehicleEntity::class,
            parentColumns = ["id"],
            childColumns = ["vehicleId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("vehicleId")],
)
data class CustomCostEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val vehicleId: Long,
    val label: String,
    val perKm: Double,
)

data class VehicleWithCosts(
    @Embedded val vehicle: VehicleEntity,
    @Relation(parentColumn = "id", entityColumn = "vehicleId")
    val customCosts: List<CustomCostEntity>,
)

/** Corrida realizada (registrada pelo motorista). */
@Entity(tableName = "trips", indices = [Index("startedAt"), Index("offerId")])
data class TripEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val offerId: Long?,
    val vehicleId: Long?,
    val startedAt: Long,
    val fare: Double,
    val pickupKm: Double?,
    val tripKm: Double?,
    val totalKm: Double?,
    val pickupMin: Double?,
    val tripMin: Double?,
    val totalMin: Double?,
    val revenuePerKm: Double?,
    val revenuePerHour: Double?,
    val fuelCost: Double?,
    val operationalCost: Double?,
    val estimatedCost: Double?,
    val estimatedProfit: Double?,
    val costPartial: Boolean,
    val classification: String?,
    val recognitionConfidence: Double?,
    val source: String,
    val category: String?,
    val origin: String?,
    val destination: String?,
    val notes: String?,
    val createdAt: Long,
    val updatedAt: Long,
)

/** Oferta analisada (vista na tela). Não é corrida realizada. */
@Entity(tableName = "analyzed_offers", indices = [Index("detectedAt"), Index("fingerprint")])
data class AnalyzedOfferEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
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
    val classification: String,
    val score: Double?,
    val headline: String,
    val confidence: Double,
    val source: String,
    val category: String?,
    val origin: String?,
    val destination: String?,
    val surge: Double?,
    val registeredTripId: Long?,
)

/** Período em que o assistente esteve ativo (base do "tempo online"). */
@Entity(tableName = "work_sessions", indices = [Index("startedAt")])
data class WorkSessionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val startedAt: Long,
    /** Atualizado periodicamente enquanto a sessão está ativa. */
    val endedAt: Long,
)
