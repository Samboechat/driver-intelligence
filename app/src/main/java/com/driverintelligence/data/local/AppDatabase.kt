package com.driverintelligence.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

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
        OfferOutcomeEntity::class,
        TripTimingEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun vehicleDao(): VehicleDao
    abstract fun tripDao(): TripDao
    abstract fun offerDao(): OfferDao
    abstract fun sessionDao(): SessionDao
    abstract fun intelligenceDao(): IntelligenceDao

    companion object {
        const val NAME = "driver_intelligence.db"

        /** v2: resultado das ofertas (aceita/recusada) e tempos reais das corridas. Não altera tabelas existentes. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `offer_outcomes` (`offerId` INTEGER NOT NULL, `outcome` TEXT NOT NULL, " +
                        "`source` TEXT NOT NULL, `decidedAt` INTEGER NOT NULL, PRIMARY KEY(`offerId`))",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `trip_timings` (`tripId` INTEGER NOT NULL, `acceptedAt` INTEGER NOT NULL, " +
                        "`arrivedAt` INTEGER, `startedAt` INTEGER, `completedAt` INTEGER, `offeredPickupMin` REAL, " +
                        "`offeredTripMin` REAL, `actualPickupMin` REAL, `actualTripMin` REAL, `autoDetected` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`tripId`))",
                )
            }
        }

        val MIGRATIONS: Array<Migration> = arrayOf(MIGRATION_1_2)
    }
}
