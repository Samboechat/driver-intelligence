package com.driverintelligence.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.driverintelligence.domain.model.AppSettings
import com.driverintelligence.domain.model.CapturePrefs
import com.driverintelligence.domain.model.CaptureRegion
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.IntelligencePrefs
import com.driverintelligence.domain.model.OverlayPrefs
import com.driverintelligence.domain.model.ScoringConfig
import com.driverintelligence.domain.model.ScoringWeights
import com.driverintelligence.domain.model.ThemeMode
import com.driverintelligence.domain.overlay.OverlayMode
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/** Preferências do motorista (metas, critérios, overlay, captura). Armazenadas localmente via DataStore. */
@Singleton
class SettingsRepository @Inject constructor(@ApplicationContext private val context: Context) {

    private object K {
        val goalDailyRevenue = doublePreferencesKey("goal_daily_revenue")
        val goalDailyProfit = doublePreferencesKey("goal_daily_profit")
        val goalWeeklyRevenue = doublePreferencesKey("goal_weekly_revenue")
        val goalMonthlyRevenue = doublePreferencesKey("goal_monthly_revenue")
        val goalMaxHours = doublePreferencesKey("goal_max_daily_hours")
        val minRevKm = doublePreferencesKey("min_revenue_per_km")
        val minRevHour = doublePreferencesKey("min_revenue_per_hour")
        val minProfitKm = doublePreferencesKey("min_profit_per_km")
        val minProfitHour = doublePreferencesKey("min_profit_per_hour")
        val minProfitTrip = doublePreferencesKey("min_profit_per_trip")
        val maxPickupMin = doublePreferencesKey("max_pickup_minutes")
        val maxUnproductive = doublePreferencesKey("max_unproductive_share")
        val maxCostShare = doublePreferencesKey("max_cost_share")
        val maxTotalKm = doublePreferencesKey("max_total_km")

        val wRevKm = doublePreferencesKey("w_revenue_km")
        val wProfitKm = doublePreferencesKey("w_profit_km")
        val wRevHour = doublePreferencesKey("w_revenue_hour")
        val wProfitHour = doublePreferencesKey("w_profit_hour")
        val wPickup = doublePreferencesKey("w_pickup_time")
        val wUnproductive = doublePreferencesKey("w_unproductive")
        val wCost = doublePreferencesKey("w_cost_share")
        val greenThreshold = doublePreferencesKey("green_threshold")
        val yellowThreshold = doublePreferencesKey("yellow_threshold")
        val minConfidence = doublePreferencesKey("min_confidence")

        val emptyReturnMode = stringPreferencesKey("empty_return_mode")
        val emptyReturnValue = doublePreferencesKey("empty_return_value")

        val overlayMode = stringPreferencesKey("overlay_mode")
        val overlayOpacity = floatPreferencesKey("overlay_opacity")
        val overlayRelX = floatPreferencesKey("overlay_rel_x")
        val overlayRelY = floatPreferencesKey("overlay_rel_y")
        val overlayHaptics = booleanPreferencesKey("overlay_haptics")
        val overlayTextScale = floatPreferencesKey("overlay_text_scale")
        val overlayDailyProgress = booleanPreferencesKey("overlay_daily_progress")

        val captureActiveMs = longPreferencesKey("capture_active_ms")
        val captureIdleMs = longPreferencesKey("capture_idle_ms")
        val captureRegion = stringPreferencesKey("capture_region")
        val captureContrast = booleanPreferencesKey("capture_contrast")
        val captureMaxWidth = intPreferencesKey("capture_max_width")

        val intPickup = doublePreferencesKey("int_default_pickup_factor")
        val intTrip = doublePreferencesKey("int_default_trip_factor")
        val intRealistic = booleanPreferencesKey("int_use_realistic")
        val intAutoTrack = booleanPreferencesKey("int_auto_track")
        val intAutoRegister = booleanPreferencesKey("int_auto_register")

        val theme = stringPreferencesKey("theme")
        val onboardingDone = booleanPreferencesKey("onboarding_done")
    }

    val settings: Flow<AppSettings> = context.settingsStore.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { it.toSettings() }
        .distinctUntilChanged()

    suspend fun updateGoals(goals: Goals) = edit { p ->
        p.putOrRemove(K.goalDailyRevenue, goals.dailyRevenue)
        p.putOrRemove(K.goalDailyProfit, goals.dailyProfit)
        p.putOrRemove(K.goalWeeklyRevenue, goals.weeklyRevenue)
        p.putOrRemove(K.goalMonthlyRevenue, goals.monthlyRevenue)
        p.putOrRemove(K.goalMaxHours, goals.maxDailyHours)
        p[K.minRevKm] = goals.minRevenuePerKm
        p[K.minRevHour] = goals.minRevenuePerHour
        p[K.minProfitKm] = goals.minProfitPerKm
        p[K.minProfitHour] = goals.minProfitPerHour
        p.putOrRemove(K.minProfitTrip, goals.minProfitPerTrip)
        p[K.maxPickupMin] = goals.maxPickupMinutes
        p[K.maxUnproductive] = goals.maxUnproductiveShare
        p[K.maxCostShare] = goals.maxCostShare
        p.putOrRemove(K.maxTotalKm, goals.maxTotalDistanceKm)
    }

    suspend fun updateScoring(config: ScoringConfig) = edit { p ->
        val w = config.weights
        p[K.wRevKm] = w.revenuePerKm
        p[K.wProfitKm] = w.profitPerKm
        p[K.wRevHour] = w.revenuePerHour
        p[K.wProfitHour] = w.profitPerHour
        p[K.wPickup] = w.pickupTime
        p[K.wUnproductive] = w.unproductiveDistance
        p[K.wCost] = w.costShare
        p[K.greenThreshold] = config.greenThreshold
        p[K.yellowThreshold] = config.yellowThreshold
        p[K.minConfidence] = config.minRecognitionConfidence
    }

    suspend fun updateEmptyReturn(scenario: EmptyReturnScenario) = edit { p ->
        when (scenario) {
            EmptyReturnScenario.None -> {
                p[K.emptyReturnMode] = "NONE"
                p.remove(K.emptyReturnValue)
            }
            is EmptyReturnScenario.PercentOfTrip -> {
                p[K.emptyReturnMode] = "PERCENT"
                p[K.emptyReturnValue] = scenario.percent
            }
            is EmptyReturnScenario.FixedDistance -> {
                p[K.emptyReturnMode] = "FIXED"
                p[K.emptyReturnValue] = scenario.km
            }
        }
    }

    suspend fun updateOverlay(transform: (OverlayPrefs) -> OverlayPrefs) = edit { p ->
        val next = transform(p.overlayPrefs())
        p[K.overlayMode] = next.mode.name
        p[K.overlayOpacity] = next.opacity.coerceIn(0.5f, 1f)
        p[K.overlayRelX] = next.relX.coerceIn(0f, 1f)
        p[K.overlayRelY] = next.relY.coerceIn(0f, 1f)
        p[K.overlayHaptics] = next.haptics
        p[K.overlayTextScale] = next.textScale.coerceIn(0.85f, 1.4f)
        p[K.overlayDailyProgress] = next.showDailyProgress
    }

    suspend fun updateCapture(transform: (CapturePrefs) -> CapturePrefs) = edit { p ->
        val next = transform(p.capturePrefs())
        p[K.captureActiveMs] = next.activeIntervalMs.coerceIn(300, 3000)
        p[K.captureIdleMs] = next.idleIntervalMs.coerceIn(500, 5000)
        p[K.captureRegion] = next.region.name
        p[K.captureContrast] = next.enhanceContrast
        p[K.captureMaxWidth] = next.maxWidth.coerceIn(540, 1440)
    }

    suspend fun updateIntelligence(transform: (IntelligencePrefs) -> IntelligencePrefs) = edit { p ->
        val d = IntelligencePrefs()
        val cur = IntelligencePrefs(
            defaultPickupFactor = p[K.intPickup] ?: d.defaultPickupFactor,
            defaultTripFactor = p[K.intTrip] ?: d.defaultTripFactor,
            useRealisticTime = p[K.intRealistic] ?: d.useRealisticTime,
            autoTrack = p[K.intAutoTrack] ?: d.autoTrack,
            autoRegister = p[K.intAutoRegister] ?: d.autoRegister,
        )
        val n = transform(cur)
        p[K.intPickup] = n.defaultPickupFactor.coerceIn(1.0, 3.0)
        p[K.intTrip] = n.defaultTripFactor.coerceIn(1.0, 3.0)
        p[K.intRealistic] = n.useRealisticTime
        p[K.intAutoTrack] = n.autoTrack
        p[K.intAutoRegister] = n.autoRegister
    }

    suspend fun setTheme(mode: ThemeMode) = edit { it[K.theme] = mode.name }

    suspend fun setOnboardingDone(done: Boolean) = edit { it[K.onboardingDone] = done }

    private suspend fun edit(block: (MutablePreferences) -> Unit) {
        context.settingsStore.edit { block(it) }
    }

    private fun MutablePreferences.putOrRemove(key: Preferences.Key<Double>, value: Double?) {
        if (value == null || !value.isFinite()) remove(key) else this[key] = value
    }

    private fun Preferences.overlayPrefs(): OverlayPrefs {
        val d = OverlayPrefs()
        return OverlayPrefs(
            mode = this[K.overlayMode]?.let { v -> OverlayMode.entries.firstOrNull { it.name == v } } ?: d.mode,
            opacity = this[K.overlayOpacity] ?: d.opacity,
            relX = this[K.overlayRelX] ?: d.relX,
            relY = this[K.overlayRelY] ?: d.relY,
            haptics = this[K.overlayHaptics] ?: d.haptics,
            textScale = this[K.overlayTextScale] ?: d.textScale,
            showDailyProgress = this[K.overlayDailyProgress] ?: d.showDailyProgress,
        )
    }

    private fun Preferences.capturePrefs(): CapturePrefs {
        val d = CapturePrefs()
        return CapturePrefs(
            activeIntervalMs = this[K.captureActiveMs] ?: d.activeIntervalMs,
            idleIntervalMs = this[K.captureIdleMs] ?: d.idleIntervalMs,
            region = this[K.captureRegion]?.let { v -> CaptureRegion.entries.firstOrNull { it.name == v } } ?: d.region,
            enhanceContrast = this[K.captureContrast] ?: d.enhanceContrast,
            maxWidth = this[K.captureMaxWidth] ?: d.maxWidth,
        )
    }

    private fun Preferences.toSettings(): AppSettings {
        val g = Goals()
        val goals = Goals(
            dailyRevenue = this[K.goalDailyRevenue],
            dailyProfit = this[K.goalDailyProfit],
            weeklyRevenue = this[K.goalWeeklyRevenue],
            monthlyRevenue = this[K.goalMonthlyRevenue],
            maxDailyHours = this[K.goalMaxHours],
            minRevenuePerKm = this[K.minRevKm] ?: g.minRevenuePerKm,
            minRevenuePerHour = this[K.minRevHour] ?: g.minRevenuePerHour,
            minProfitPerKm = this[K.minProfitKm] ?: g.minProfitPerKm,
            minProfitPerHour = this[K.minProfitHour] ?: g.minProfitPerHour,
            minProfitPerTrip = this[K.minProfitTrip],
            maxPickupMinutes = this[K.maxPickupMin] ?: g.maxPickupMinutes,
            maxUnproductiveShare = this[K.maxUnproductive] ?: g.maxUnproductiveShare,
            maxCostShare = this[K.maxCostShare] ?: g.maxCostShare,
            maxTotalDistanceKm = this[K.maxTotalKm],
        )
        val dw = ScoringWeights()
        val ds = ScoringConfig()
        val scoring = ScoringConfig(
            weights = ScoringWeights(
                revenuePerKm = this[K.wRevKm] ?: dw.revenuePerKm,
                profitPerKm = this[K.wProfitKm] ?: dw.profitPerKm,
                revenuePerHour = this[K.wRevHour] ?: dw.revenuePerHour,
                profitPerHour = this[K.wProfitHour] ?: dw.profitPerHour,
                pickupTime = this[K.wPickup] ?: dw.pickupTime,
                unproductiveDistance = this[K.wUnproductive] ?: dw.unproductiveDistance,
                costShare = this[K.wCost] ?: dw.costShare,
            ),
            greenThreshold = this[K.greenThreshold] ?: ds.greenThreshold,
            yellowThreshold = this[K.yellowThreshold] ?: ds.yellowThreshold,
            minRecognitionConfidence = this[K.minConfidence] ?: ds.minRecognitionConfidence,
        )
        val erValue = this[K.emptyReturnValue]
        val emptyReturn = when (this[K.emptyReturnMode]) {
            "PERCENT" -> erValue?.let { EmptyReturnScenario.PercentOfTrip(it) } ?: EmptyReturnScenario.None
            "FIXED" -> erValue?.let { EmptyReturnScenario.FixedDistance(it) } ?: EmptyReturnScenario.None
            else -> EmptyReturnScenario.None
        }
        return AppSettings(
            goals = goals,
            scoring = scoring,
            emptyReturn = emptyReturn,
            overlay = overlayPrefs(),
            capture = capturePrefs(),
            intelligence = IntelligencePrefs().let { d ->
                IntelligencePrefs(
                    defaultPickupFactor = this[K.intPickup] ?: d.defaultPickupFactor,
                    defaultTripFactor = this[K.intTrip] ?: d.defaultTripFactor,
                    useRealisticTime = this[K.intRealistic] ?: d.useRealisticTime,
                    autoTrack = this[K.intAutoTrack] ?: d.autoTrack,
                    autoRegister = this[K.intAutoRegister] ?: d.autoRegister,
                )
            },
            theme = this[K.theme]?.let { v -> ThemeMode.entries.firstOrNull { it.name == v } } ?: ThemeMode.DARK,
            onboardingDone = this[K.onboardingDone] ?: false,
        )
    }
}
