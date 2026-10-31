package com.driverintelligence.features.home

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.driverintelligence.capture.AssistantController
import com.driverintelligence.capture.AssistantState
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.SessionRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.data.repository.VehicleRepository
import com.driverintelligence.domain.analytics.AnalyticsEngine
import com.driverintelligence.domain.analytics.PeriodSummary
import com.driverintelligence.domain.analytics.SeriesPoint
import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.Vehicle
import com.driverintelligence.permissions.PermissionSnapshot
import com.driverintelligence.permissions.Permissions
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.time.LocalDate
import javax.inject.Inject

data class HomeUiState(
    val today: PeriodSummary = PeriodSummary.EMPTY,
    val goals: Goals = Goals(),
    val last7: List<SeriesPoint> = emptyList(),
    val recentOffers: List<AnalyzedOffer> = emptyList(),
    val assistant: AssistantState = AssistantState(),
    val vehicle: Vehicle? = null,
    val permissions: PermissionSnapshot? = null,
    val loaded: Boolean = false,
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    @ApplicationContext private val appContext: Context,
    trips: TripRepository,
    offers: OfferRepository,
    sessions: SessionRepository,
    vehicles: VehicleRepository,
    settings: SettingsRepository,
    private val controller: AssistantController,
    private val analytics: AnalyticsEngine,
) : ViewModel() {

    private val permissions = MutableStateFlow<PermissionSnapshot?>(null)

    private val data = combine(trips.trips, sessions.sessions, offers.recent(5)) { t, s, o -> Triple(t, s, o) }
    private val context = combine(vehicles.activeVehicle, settings.settings, controller.state, permissions) { v, st, a, p -> Ctx(v, st.goals, a, p) }

    private data class Ctx(val vehicle: Vehicle?, val goals: Goals, val assistant: AssistantState, val permissions: PermissionSnapshot?)

    val state: StateFlow<HomeUiState> = combine(data, context) { (trips, sessions, offers), ctx ->
        val today = LocalDate.now()
        val (from, to) = analytics.dayRange(today)
        val records = trips.map { it.toRecord() }
        HomeUiState(
            today = analytics.summary(records, sessions, from, to),
            goals = ctx.goals,
            last7 = analytics.daily(records, today, 7),
            recentOffers = offers,
            assistant = ctx.assistant,
            vehicle = ctx.vehicle,
            permissions = ctx.permissions,
            loaded = true,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState())

    fun refreshPermissions() {
        permissions.value = Permissions.snapshot(appContext)
    }

    fun startAssistant(context: Context) = controller.requestStart(context)
    fun stopAssistant(context: Context) = controller.stop(context)
    fun pauseAssistant(context: Context) = controller.pause(context)
    fun resumeAssistant(context: Context) = controller.resume(context)
}
