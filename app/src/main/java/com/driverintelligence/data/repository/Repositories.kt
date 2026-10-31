package com.driverintelligence.data.repository

import com.driverintelligence.data.local.AnalyzedOfferEntity
import com.driverintelligence.data.local.IntelligenceDao
import com.driverintelligence.data.local.OfferDao
import com.driverintelligence.data.local.OfferOutcomeEntity
import com.driverintelligence.data.local.TripTimingEntity
import com.driverintelligence.data.local.enumOr
import com.driverintelligence.data.local.SessionDao
import com.driverintelligence.data.local.TripDao
import com.driverintelligence.data.local.TripEntity
import com.driverintelligence.data.local.VehicleDao
import com.driverintelligence.data.local.WorkSessionEntity
import com.driverintelligence.data.local.customCostEntities
import com.driverintelligence.data.local.toDomain
import com.driverintelligence.data.local.toEntity
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.domain.analytics.OfferBenchmark
import com.driverintelligence.domain.analytics.SessionRecord
import com.driverintelligence.domain.analytics.TimeCalibration
import com.driverintelligence.domain.analytics.TimingSample
import com.driverintelligence.domain.detection.OfferOutcome
import com.driverintelligence.domain.detection.OutcomeSource
import com.driverintelligence.domain.detection.TripTimeline
import com.driverintelligence.domain.model.TripTiming
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
    private val intelligenceDao: IntelligenceDao,
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
        intelligenceDao.deleteTiming(id)
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
class OfferRepository @Inject constructor(private val dao: OfferDao, private val intelligenceDao: IntelligenceDao) {
    private val outcomes = intelligenceDao.observeOutcomes().map { list -> list.associateBy { it.offerId } }

    private fun withOutcomes(flow: Flow<List<AnalyzedOfferEntity>>): Flow<List<AnalyzedOffer>> =
        combine(flow, outcomes) { list, map ->
            list.map { e ->
                val o = map[e.id]
                e.toDomain().copy(
                    outcome = o?.let { enumOr(it.outcome, OfferOutcome.UNKNOWN) },
                    outcomeSource = o?.let { enumOr(it.source, OutcomeSource.DETECTED) },
                )
            }
        }

    val all: Flow<List<AnalyzedOffer>> = withOutcomes(dao.observeAll())

    fun recent(limit: Int): Flow<List<AnalyzedOffer>> = withOutcomes(dao.observeRecent(limit))

    /** Registra o que o motorista fez com a oferta (aceita, recusada, ignorada). */
    suspend fun setOutcome(offerId: Long, outcome: OfferOutcome, source: OutcomeSource, at: Long) =
        intelligenceDao.upsertOutcome(OfferOutcomeEntity(offerId, outcome.name, source.name, at))

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

    suspend fun delete(id: Long) {
        intelligenceDao.deleteOutcome(id)
        dao.delete(id)
    }

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
    intelligence: IntelligenceRepository,
    offerDao: OfferDao,
) {
    private val benchmark = offerDao.observeRecent(300).map { list -> OfferBenchmark(list.mapNotNull { it.revenuePerKm }) }

    val context: Flow<AnalysisContext> = combine(vehicles.activeVehicle, settings.settings, intelligence.samples, benchmark) { vehicle, s, samples, bench ->
        AnalysisContext(
            costs = vehicle?.toCostProfile() ?: CostProfile.EMPTY,
            goals = s.goals,
            scoring = s.scoring,
            emptyReturn = s.emptyReturn,
            vehicleId = vehicle?.id,
            calibration = TimeCalibration(samples, s.intelligence.defaultPickupFactor, s.intelligence.defaultTripFactor),
            benchmark = bench,
            useRealisticTime = s.intelligence.useRealisticTime,
        )
    }
}

/** Resultados das ofertas e tempos reais das corridas: a "memória" que deixa a análise mais precisa. */
@Singleton
class IntelligenceRepository @Inject constructor(
    private val dao: IntelligenceDao,
    private val trips: TripRepository,
    private val offerDao: OfferDao,
) {
    val timings: Flow<List<TripTiming>> = dao.observeTimings().map { list -> list.map { it.toDomain() } }

    val samples: Flow<List<TimingSample>> = timings.map { list ->
        list.map { TimingSample(it.acceptedAt, it.offeredPickupMin, it.actualPickupMin, it.offeredTripMin, it.actualTripMin) }
    }

    /**
     * Corrida acompanhada do aceite ao fim: registra como REALIZADA com os tempos reais
     * (indicadores recalculados) e guarda o par prometido × real para o aprendizado.
     */
    suspend fun saveCompletedTrip(tl: TripTimeline, offerId: Long?, ctx: AnalysisContext, register: Boolean): Long? {
        val offer = tl.offer.offer
        var tripId: Long? = offerId?.let { offerDao.get(it)?.registeredTripId }
        if (register && tripId == null) {
            val actual = offer.copy(pickupTimeMin = tl.actualPickupMin ?: offer.pickupTimeMin, tripTimeMin = tl.actualTripMin ?: offer.tripTimeMin)
            val base = Trip.fromAnalysis(tl.offer, tl.acceptedAt, ctx.vehicleId, offerId).copy(
                pickupMin = actual.pickupTimeMin,
                tripMin = actual.tripTimeMin,
                notes = "Registrada automaticamente · tempos reais medidos",
            )
            tripId = trips.save(base.recalculated(ctx))
            if (offerId != null) offerDao.markRegistered(offerId, tripId)
        }
        val id = tripId ?: return null
        dao.upsertTiming(
            TripTimingEntity(
                tripId = id,
                acceptedAt = tl.acceptedAt,
                arrivedAt = tl.arrivedAt,
                startedAt = tl.startedAt,
                completedAt = tl.completedAt,
                offeredPickupMin = offer.pickupTimeMin,
                offeredTripMin = offer.tripTimeMin,
                actualPickupMin = tl.actualPickupMin,
                actualTripMin = tl.actualTripMin,
                autoDetected = tl.acceptSource == OutcomeSource.DETECTED,
            ),
        )
        return id
    }
}
