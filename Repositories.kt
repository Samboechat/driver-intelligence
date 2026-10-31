package com.driverintelligence.data.repository

import com.driverintelligence.data.local.OfferDao
import com.driverintelligence.data.local.SessionDao
import com.driverintelligence.data.local.TripDao
import com.driverintelligence.data.local.TripEntity
import com.driverintelligence.data.local.VehicleDao
import com.driverintelligence.data.local.WorkSessionEntity
import com.driverintelligence.data.local.customCostEntities
import com.driverintelligence.data.local.toDomain
import com.driverintelligence.data.local.toEntity
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.domain.analytics.SessionRecord
import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.model.Vehicle
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OfferAnalysis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VehicleRepository @Inject constructor(private val dao: VehicleDao) {
    val vehicles: Flow<List<Vehicle>> = dao.observeAll().map { list -> list.map { it.toDomain() } }
    val activeVehicle: Flow<Vehicle?> = dao.observeActive().map { it?.toDomain() }.distinctUntilChanged()

    suspend fun get(id: Long): Vehicle? = dao.get(id)?.toDomain()

    suspend fun save(vehicle: Vehicle): Long {
        val now = System.currentTimeMillis()
        val createdAt = if (vehicle.id != 0L) dao.get(vehicle.id)?.vehicle?.createdAt ?: now else now
        return dao.saveWithCosts(vehicle.toEntity(createdAt, now), vehicle.customCostEntities())
    }

    suspend fun delete(id: Long) = dao.deleteAndReassign(id)

    suspend fun setActive(id: Long) = dao.setActive(id)
}

@Singleton
class TripRepository @Inject constructor(
    private val dao: TripDao,
    private val offerDao: OfferDao,
) {
    val trips: Flow<List<Trip>> = dao.observeAll().map { list -> list.map(TripEntity::toDomain) }

    fun tripsBetween(from: Long, to: Long): Flow<List<Trip>> =
        dao.observeBetween(from, to).map { list -> list.map(TripEntity::toDomain) }

    suspend fun get(id: Long): Trip? = dao.get(id)?.toDomain()

    suspend fun save(trip: Trip): Long {
        val now = System.currentTimeMillis()
        return if (trip.id == 0L) {
            dao.insert(trip.toEntity(now, now))
        } else {
            val createdAt = dao.get(trip.id)?.createdAt ?: now
            dao.update(trip.toEntity(createdAt, now))
            trip.id
        }
    }

    suspend fun delete(id: Long) {
        offerDao.unlinkTrip(id)
        dao.delete(id)
    }

    /**
     * Registra como corrida realizada uma oferta analisada — ação explícita do motorista.
     * Idempotente: a mesma oferta nunca gera duas corridas.
     */
    suspend fun registerFromOffer(offer: AnalyzedOffer): Long {
        offer.registeredTripId?.let { return it }
        if (offer.id != 0L && dao.countForOffer(offer.id) > 0) {
            return offerDao.get(offer.id)?.registeredTripId ?: error("Oferta já registrada")
        }
        val trip = Trip(
            offerId = offer.id.takeIf { it != 0L },
            vehicleId = offer.vehicleId,
            startedAt = offer.detectedAt,
            fare = offer.fare ?: 0.0,
            pickupKm = offer.pickupKm,
            tripKm = offer.tripKm,
            totalKm = offer.totalKm,
            pickupMin = offer.pickupMin,
            tripMin = offer.tripMin,
            totalMin = offer.totalMin,
            revenuePerKm = offer.revenuePerKm,
            revenuePerHour = offer.revenuePerHour,
            estimatedCost = offer.estimatedCost,
            estimatedProfit = offer.estimatedProfit,
            costPartial = offer.costPartial,
            classification = offer.classification,
            recognitionConfidence = offer.confidence,
            source = offer.source,
            category = offer.category,
            origin = offer.origin,
            destination = offer.destination,
        )
        val id = save(trip)
        if (offer.id != 0L) offerDao.markRegistered(offer.id, id)
        return id
    }
}

@Singleton
class OfferRepository @Inject constructor(private val dao: OfferDao) {
    val all: Flow<List<AnalyzedOffer>> = dao.observeAll().map { list -> list.map { it.toDomain() } }

    fun recent(limit: Int): Flow<List<AnalyzedOffer>> = dao.observeRecent(limit).map { list -> list.map { it.toDomain() } }

    suspend fun get(id: Long): AnalyzedOffer? = dao.get(id)?.toDomain()

    /**
     * Registra uma oferta ANALISADA. Deduplicação por impressão digital dentro da janela:
     * a mesma oferta reexibida não cria um segundo registro.
     */
    suspend fun record(analysis: OfferAnalysis, vehicleId: Long?, now: Long = System.currentTimeMillis(), dedupWindowMs: Long = 120_000): Long? {
        val fp = analysis.fingerprint ?: return null
        dao.findRecent(fp, now - dedupWindowMs)?.let { return it.id }
        return dao.insert(AnalyzedOffer.from(analysis, now, vehicleId).toEntity())
    }

    suspend fun delete(id: Long) = dao.delete(id)

    /** Política de retenção: ofertas não registradas mais antigas que [days] dias. */
    suspend fun purgeOlderThan(days: Int, now: Long = System.currentTimeMillis()): Int =
        dao.deleteOlderThan(now - days * 86_400_000L)
}

@Singleton
class SessionRepository @Inject constructor(private val dao: SessionDao) {
    val sessions: Flow<List<SessionRecord>> = dao.observeAll().map { list -> list.map { SessionRecord(it.startedAt, it.endedAt) } }

    suspend fun start(now: Long): Long = dao.insert(WorkSessionEntity(startedAt = now, endedAt = now))

    suspend fun heartbeat(id: Long, now: Long) = dao.touch(id, now)
}

/** Combina veículo ativo + preferências no contexto usado em cada análise. */
@Singleton
class AnalysisContextProvider @Inject constructor(
    vehicles: VehicleRepository,
    settings: SettingsRepository,
) {
    val context: Flow<AnalysisContext> = combine(vehicles.activeVehicle, settings.settings) { vehicle, s ->
        AnalysisContext(
            costs = vehicle?.toCostProfile() ?: CostProfile.EMPTY,
            goals = s.goals,
            scoring = s.scoring,
            emptyReturn = s.emptyReturn,
            vehicleId = vehicle?.id,
        )
    }.distinctUntilChanged()
}
