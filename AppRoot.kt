package com.driverintelligence.features.navigation

import android.net.Uri
import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.driverintelligence.R
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.features.history.HistoryScreen
import com.driverintelligence.features.history.TripEditScreen
import com.driverintelligence.features.home.HomeScreen
import com.driverintelligence.features.manual.ManualAnalysisScreen
import com.driverintelligence.features.ocrlab.OcrLabScreen
import com.driverintelligence.features.onboarding.PermissionsScreen
import com.driverintelligence.features.settings.GoalsScreen
import com.driverintelligence.features.settings.PrivacyScreen
import com.driverintelligence.features.settings.ScoringScreen
import com.driverintelligence.features.settings.SettingsScreen
import com.driverintelligence.features.statistics.StatisticsScreen
import com.driverintelligence.features.vehicles.VehicleEditScreen
import com.driverintelligence.features.vehicles.VehiclesScreen
import kotlinx.coroutines.flow.MutableStateFlow

sealed interface LaunchRequest {
    data class Manual(
        val fare: Double?,
        val pickupKm: Double?,
        val tripKm: Double?,
        val pickupMin: Double?,
        val tripMin: Double?,
    ) : LaunchRequest
}

object Routes {
    const val HOME = "home"
    const val HISTORY = "history"
    const val STATS = "stats"
    const val VEHICLES = "vehicles"
    const val SETTINGS = "settings"
    const val ONBOARDING = "onboarding"
    const val PERMISSIONS = "permissions"
    const val GOALS = "goals"
    const val SCORING = "scoring"
    const val PRIVACY = "privacy"
    const val OCR_LAB = "ocrlab"
    const val VEHICLE_EDIT = "vehicle/{id}"
    const val TRIP_EDIT = "trip/{id}"
    const val MANUAL = "manual?fare={fare}&pk={pk}&tk={tk}&pm={pm}&tm={tm}"

    fun vehicle(id: Long) = "vehicle/$id"
    fun trip(id: Long) = "trip/$id"
    fun manual(r: LaunchRequest.Manual? = null): String {
        fun v(d: Double?) = d?.toString()?.let(Uri::encode).orEmpty()
        return if (r == null) "manual" else "manual?fare=${v(r.fare)}&pk=${v(r.pickupKm)}&tk=${v(r.tripKm)}&pm=${v(r.pickupMin)}&tm=${v(r.tripMin)}"
    }
}

private data class Tab(val route: String, val label: String, @DrawableRes val icon: Int)

private val tabs = listOf(
    Tab(Routes.HOME, "Início", R.drawable.ic_nav_home),
    Tab(Routes.HISTORY, "Histórico", R.drawable.ic_nav_history),
    Tab(Routes.STATS, "Estatísticas", R.drawable.ic_nav_stats),
    Tab(Routes.VEHICLES, "Veículos", R.drawable.ic_nav_car),
    Tab(Routes.SETTINGS, "Ajustes", R.drawable.ic_nav_settings),
)

@Composable
fun AppRoot(showOnboarding: Boolean, launchRequest: MutableStateFlow<LaunchRequest?>) {
    val nav = rememberNavController()
    val c = DiTheme.colors
    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val request by launchRequest.collectAsStateWithLifecycle()

    LaunchedEffect(request) {
        val r = request
        if (r is LaunchRequest.Manual) {
            nav.navigate(Routes.manual(r)) { launchSingleTop = true }
            launchRequest.value = null
        }
    }

    Column(Modifier.fillMaxSize().background(c.background)) {
        Box(Modifier.weight(1f)) {
            NavHost(
                navController = nav,
                startDestination = if (showOnboarding) Routes.ONBOARDING else Routes.HOME,
            ) {
                composable(Routes.HOME) {
                    HomeScreen(
                        onOpenPermissions = { nav.navigate(Routes.PERMISSIONS) },
                        onManual = { nav.navigate(Routes.manual()) },
                        onNewTrip = { nav.navigate(Routes.trip(0)) },
                        onOpenOffers = { nav.navigateTab(Routes.HISTORY) },
                        onAddVehicle = { nav.navigate(Routes.vehicle(0)) },
                        onOpenGoals = { nav.navigate(Routes.GOALS) },
                    )
                }
                composable(Routes.HISTORY) {
                    HistoryScreen(onEditTrip = { nav.navigate(Routes.trip(it)) }, onNewTrip = { nav.navigate(Routes.trip(0)) })
                }
                composable(Routes.STATS) { StatisticsScreen() }
                composable(Routes.VEHICLES) {
                    VehiclesScreen(onEdit = { nav.navigate(Routes.vehicle(it)) }, onAdd = { nav.navigate(Routes.vehicle(0)) })
                }
                composable(Routes.SETTINGS) {
                    SettingsScreen(
                        onOpenGoals = { nav.navigate(Routes.GOALS) },
                        onOpenScoring = { nav.navigate(Routes.SCORING) },
                        onOpenPermissions = { nav.navigate(Routes.PERMISSIONS) },
                        onOpenOcrLab = { nav.navigate(Routes.OCR_LAB) },
                        onOpenPrivacy = { nav.navigate(Routes.PRIVACY) },
                    )
                }
                composable(Routes.ONBOARDING) {
                    PermissionsScreen(
                        onboarding = true,
                        onBack = null,
                        onConfigureVehicle = { nav.navigate(Routes.vehicle(0)) },
                        onFinish = {
                            nav.navigate(Routes.HOME) { popUpTo(Routes.ONBOARDING) { inclusive = true } }
                        },
                    )
                }
                composable(Routes.PERMISSIONS) {
                    PermissionsScreen(onboarding = false, onBack = { nav.popBackStack() }, onConfigureVehicle = { nav.navigate(Routes.vehicle(0)) }, onFinish = { nav.popBackStack() })
                }
                composable(Routes.GOALS) { GoalsScreen(onBack = { nav.popBackStack() }) }
                composable(Routes.SCORING) { ScoringScreen(onBack = { nav.popBackStack() }) }
                composable(Routes.PRIVACY) { PrivacyScreen(onBack = { nav.popBackStack() }) }
                composable(Routes.OCR_LAB) { OcrLabScreen(onBack = { nav.popBackStack() }) }
                composable(Routes.VEHICLE_EDIT, arguments = listOf(navArgument("id") { type = NavType.LongType })) {
                    VehicleEditScreen(onBack = { nav.popBackStack() })
                }
                composable(Routes.TRIP_EDIT, arguments = listOf(navArgument("id") { type = NavType.LongType })) {
                    TripEditScreen(onBack = { nav.popBackStack() })
                }
                composable(
                    Routes.MANUAL,
                    arguments = listOf("fare", "pk", "tk", "pm", "tm").map { name ->
                        navArgument(name) {
                            type = NavType.StringType
                            nullable = true
                            defaultValue = null
                        }
                    },
                ) {
                    ManualAnalysisScreen(onBack = { nav.popBackStack() }, onOpenTrips = { nav.navigateTab(Routes.HISTORY) })
                }
            }
        }
        if (currentRoute in tabs.map { it.route }) {
            NavigationBar(
                containerColor = c.surface,
                tonalElevation = 0.dp,
            ) {
                tabs.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute == tab.route,
                        onClick = { nav.navigateTab(tab.route) },
                        icon = { Icon(painterResource(tab.icon), contentDescription = null, modifier = Modifier.size(22.dp)) },
                        label = { Text(tab.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = c.textPrimary,
                            selectedTextColor = c.textPrimary,
                            unselectedIconColor = c.textTertiary,
                            unselectedTextColor = c.textTertiary,
                            indicatorColor = c.brandSoft,
                        ),
                    )
                }
            }
        }
    }
}

private fun NavHostController.navigateTab(route: String) {
    navigate(route) {
        // HOME é sempre a base após o onboarding.
        popUpTo(Routes.HOME) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
