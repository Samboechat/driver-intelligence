package com.driverintelligence.features.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.driverintelligence.capture.AssistantController
import com.driverintelligence.capture.AssistantState
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.domain.model.AppSettings
import com.driverintelligence.domain.model.CapturePrefs
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.OverlayPrefs
import com.driverintelligence.domain.model.ScoringConfig
import com.driverintelligence.domain.model.ThemeMode
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val repo: SettingsRepository,
    private val offers: OfferRepository,
    controller: AssistantController,
) : ViewModel() {
    val settings: StateFlow<AppSettings?> = repo.settings.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
    val assistant: StateFlow<AssistantState> = controller.state

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    fun saveGoals(goals: Goals) = viewModelScope.launch {
        repo.updateGoals(goals)
        _message.value = "Metas salvas."
    }

    fun saveScoring(config: ScoringConfig) = viewModelScope.launch {
        repo.updateScoring(config)
        _message.value = "Critérios salvos."
    }

    fun setEmptyReturn(s: EmptyReturnScenario) = viewModelScope.launch { repo.updateEmptyReturn(s) }
    fun updateOverlay(t: (OverlayPrefs) -> OverlayPrefs) = viewModelScope.launch { repo.updateOverlay(t) }
    fun updateCapture(t: (CapturePrefs) -> CapturePrefs) = viewModelScope.launch { repo.updateCapture(t) }
    fun setTheme(mode: ThemeMode) = viewModelScope.launch { repo.setTheme(mode) }

    fun purgeOffers(days: Int) = viewModelScope.launch {
        val n = offers.purgeOlderThan(days)
        _message.value = "$n oferta(s) antiga(s) removida(s)."
    }

    fun clearMessage() {
        _message.value = null
    }
}
