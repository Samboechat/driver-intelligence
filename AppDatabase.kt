package com.driverintelligence.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration

/**
 * Banco local. Esquema exportado em app/schemas/ (versionado no git).
 *
 * Processo de migração: ao alterar uma entidade, incremente [version], adicione um
 * Migration(N, N+1) em [MIGRATIONS] e um teste em DatabaseTest. Nunca usar migração destrutiva:
 * o histórico do motorista não pode ser perdido em atualização.
 */
@Database(
    entities = [
        VehicleEntity::class,
        CustomCostEntity::class,
        TripEntity::class,
        AnalyzedOfferEntity::class,
        WorkSessionEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun vehicleDao(): VehicleDao
    abstract fun tripDao(): TripDao
    abstract fun offerDao(): OfferDao
    abstract fun sessionDao(): SessionDao

    companion object {
        const val NAME = "driver_intelligence.db"
        val MIGRATIONS: Array<Migration> = emptyArray()
    }
}
