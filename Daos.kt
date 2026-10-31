package com.driverintelligence.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
abstract class VehicleDao {
    @Transaction
    @Query("SELECT * FROM vehicles ORDER BY isActive DESC, updatedAt DESC")
    abstract fun observeAll(): Flow<List<VehicleWithCosts>>

    @Transaction
    @Query("SELECT * FROM vehicles WHERE isActive = 1 LIMIT 1")
    abstract fun observeActive(): Flow<VehicleWithCosts?>

    @Transaction
    @Query("SELECT * FROM vehicles WHERE id = :id")
    abstract suspend fun get(id: Long): VehicleWithCosts?

    @Query("SELECT COUNT(*) FROM vehicles")
    abstract suspend fun count(): Int

    @Query("SELECT COUNT(*) FROM vehicles WHERE isActive = 1")
    abstract suspend fun activeCount(): Int

    @Insert
    abstract suspend fun insert(vehicle: VehicleEntity): Long

    @Update
    abstract suspend fun update(vehicle: VehicleEntity)

    @Query("DELETE FROM vehicles WHERE id = :id")
    abstract suspend fun delete(id: Long)

    @Query("UPDATE vehicles SET isActive = CASE WHEN id = :id THEN 1 ELSE 0 END")
    abstract suspend fun setActive(id: Long)

    @Query("SELECT id FROM vehicles ORDER BY updatedAt DESC LIMIT 1")
    abstract suspend fun latestId(): Long?

    @Query("DELETE FROM vehicle_custom_costs WHERE vehicleId = :vehicleId")
    abstract suspend fun clearCustomCosts(vehicleId: Long)

    @Insert
    abstract suspend fun insertCustomCosts(costs: List<CustomCostEntity>)

    /** Salva veículo e custos personalizados atomicamente. O primeiro veículo vira o ativo. */
    @Transaction
    open suspend fun saveWithCosts(vehicle: VehicleEntity, costs: List<CustomCostEntity>): Long {
        val id = if (vehicle.id == 0L) insert(vehicle) else {
            update(vehicle)
            vehicle.id
        }
        clearCustomCosts(id)
        if (costs.isNotEmpty()) insertCustomCosts(costs.map { it.copy(id = 0, vehicleId = id) })
        if (vehicle.isActive || activeCount() == 0) setActive(id)
        return id
    }

    /** Remove o veículo e garante que continue existindo um ativo, se houver outros. */
    @Transaction
    open suspend fun deleteAndReassign(id: Long) {
        delete(id)
        if (activeCount() == 0) latestId()?.let { setActive(it) }
    }
}

@Dao
interface TripDao {
    @Query("SELECT * FROM trips ORDER BY startedAt DESC")
    fun observeAll(): Flow<List<TripEntity>>

    @Query("SELECT * FROM trips WHERE startedAt >= :from AND startedAt < :to ORDER BY startedAt DESC")
    fun observeBetween(from: Long, to: Long): Flow<List<TripEntity>>

    @Query("SELECT * FROM trips WHERE id = :id")
    suspend fun get(id: Long): TripEntity?

    @Insert
    suspend fun insert(trip: TripEntity): Long

    @Update
    suspend fun update(trip: TripEntity)

    @Query("DELETE FROM trips WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("SELECT COUNT(*) FROM trips WHERE offerId = :offerId")
    suspend fun countForOffer(offerId: Long): Int
}

@Dao
interface OfferDao {
    @Query("SELECT * FROM analyzed_offers ORDER BY detectedAt DESC LIMIT :limit")
    fun observeRecent(limit: Int): Flow<List<AnalyzedOfferEntity>>

    @Query("SELECT * FROM analyzed_offers ORDER BY detectedAt DESC")
    fun observeAll(): Flow<List<AnalyzedOfferEntity>>

    @Query("SELECT * FROM analyzed_offers WHERE fingerprint = :fingerprint AND detectedAt >= :since ORDER BY detectedAt DESC LIMIT 1")
    suspend fun findRecent(fingerprint: String, since: Long): AnalyzedOfferEntity?

    @Query("SELECT * FROM analyzed_offers WHERE id = :id")
    suspend fun get(id: Long): AnalyzedOfferEntity?

    @Insert
    suspend fun insert(offer: AnalyzedOfferEntity): Long

    @Query("DELETE FROM analyzed_offers WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("UPDATE analyzed_offers SET registeredTripId = :tripId WHERE id = :id")
    suspend fun markRegistered(id: Long, tripId: Long?)

    @Query("UPDATE analyzed_offers SET registeredTripId = NULL WHERE registeredTripId = :tripId")
    suspend fun unlinkTrip(tripId: Long)

    @Query("DELETE FROM analyzed_offers WHERE detectedAt < :before AND registeredTripId IS NULL")
    suspend fun deleteOlderThan(before: Long): Int
}

@Dao
interface SessionDao {
    @Insert
    suspend fun insert(session: WorkSessionEntity): Long

    @Query("UPDATE work_sessions SET endedAt = :endedAt WHERE id = :id")
    suspend fun touch(id: Long, endedAt: Long)

    @Query("SELECT * FROM work_sessions ORDER BY startedAt DESC")
    fun observeAll(): Flow<List<WorkSessionEntity>>
}
