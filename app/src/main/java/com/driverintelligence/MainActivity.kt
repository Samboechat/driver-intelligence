package com.driverintelligence

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.DriverIntelligenceTheme
import com.driverintelligence.domain.model.ThemeMode
import com.driverintelligence.features.navigation.AppRoot
import com.driverintelligence.features.navigation.LaunchRequest
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.MutableStateFlow
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var settingsRepository: SettingsRepository

    private val launchRequest = MutableStateFlow<LaunchRequest?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) launchRequest.value = parse(intent)
        setContent {
            val settings by settingsRepository.settings.collectAsStateWithLifecycle(initialValue = null)
            val s = settings
            DriverIntelligenceTheme(mode = s?.theme ?: ThemeMode.DARK) {
                if (s == null) {
                    Box(Modifier.fillMaxSize().background(DiTheme.colors.background))
                } else {
                    AppRoot(
                        showOnboarding = !s.onboardingDone,
                        launchRequest = launchRequest,
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        parse(intent)?.let { launchRequest.value = it }
    }

    private fun parse(intent: Intent?): LaunchRequest? {
        if (intent?.getStringExtra(EXTRA_ROUTE) != ROUTE_MANUAL) return null
        fun d(key: String): Double? = if (intent.hasExtra(key)) intent.getDoubleExtra(key, 0.0) else null
        return LaunchRequest.Manual(
            fare = d(EXTRA_FARE),
            pickupKm = d(EXTRA_PICKUP_KM),
            tripKm = d(EXTRA_TRIP_KM),
            pickupMin = d(EXTRA_PICKUP_MIN),
            tripMin = d(EXTRA_TRIP_MIN),
        )
    }

    companion object {
        const val EXTRA_ROUTE = "route"
        const val ROUTE_MANUAL = "manual"
        const val EXTRA_FARE = "fare"
        const val EXTRA_PICKUP_KM = "pickup_km"
        const val EXTRA_TRIP_KM = "trip_km"
        const val EXTRA_PICKUP_MIN = "pickup_min"
        const val EXTRA_TRIP_MIN = "trip_min"
    }
}
