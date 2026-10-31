package com.driverintelligence.di

import android.content.Context
import androidx.room.Room
import com.driverintelligence.data.local.AppDatabase
import com.driverintelligence.data.local.OfferDao
import com.driverintelligence.data.local.SessionDao
import com.driverintelligence.data.local.TripDao
import com.driverintelligence.data.local.VehicleDao
import com.driverintelligence.domain.analytics.AnalyticsEngine
import com.driverintelligence.domain.financial.DecisionEngine
import com.driverintelligence.domain.financial.FinancialEngine
import com.driverintelligence.domain.recognition.OfferAnalyzer
import com.driverintelligence.recognition.MlKitOcrEngine
import com.driverintelligence.recognition.OcrEngine
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun database(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, AppDatabase.NAME)
            .addMigrations(*AppDatabase.MIGRATIONS)
            .build()

    @Provides fun vehicleDao(db: AppDatabase): VehicleDao = db.vehicleDao()
    @Provides fun tripDao(db: AppDatabase): TripDao = db.tripDao()
    @Provides fun offerDao(db: AppDatabase): OfferDao = db.offerDao()
    @Provides fun sessionDao(db: AppDatabase): SessionDao = db.sessionDao()
    @Provides fun intelligenceDao(db: AppDatabase): com.driverintelligence.data.local.IntelligenceDao = db.intelligenceDao()

    @Provides @Singleton fun financialEngine(): FinancialEngine = FinancialEngine()
    @Provides @Singleton fun decisionEngine(): DecisionEngine = DecisionEngine()
    @Provides @Singleton fun analyticsEngine(): AnalyticsEngine = AnalyticsEngine()

    @Provides
    @Singleton
    fun offerAnalyzer(financial: FinancialEngine, decision: DecisionEngine): OfferAnalyzer =
        OfferAnalyzer(financial = financial, decision = decision)

    /** OCR local (ML Kit, modelo embarcado no APK — nada sai do aparelho). */
    @Provides fun ocrEngine(): OcrEngine = MlKitOcrEngine()
}
