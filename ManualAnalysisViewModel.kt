package com.driverintelligence.features.manual

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.AnalysisContextProvider
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.recognition.OfferAnalyzer
import com.driverintelligence.features.common.formatInput
import com.driverintelligence.features.common.parseInput
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ManualInputs(
    val fare: String = "",
    val pickupKm: String = "",
    val pickupMin: String = "",
    val tripKm: String = "",
    val tripMin: String = "",
) {
    fun toOffer() = OfferData(
        fare = parseInput(fare),
        pickupDistanceKm = parseInput(pickupKm),
        tripDistanceKm = parseInput(tripKm),
        pickupTimeMin = parseInput(pickupMin),
        tripTimeMin = parseInput(tripMin),
    )
    val isEmpty: Boolean get() = listOf(fare, pickupKm, pickupMin, tripKm, tripMin).all { it.isBlank() }
}

data class ManualUiState(
    val inputs: ManualInputs = ManualInputs(),
    val analysis: OfferAnalysis? = null,
    val hasVehicle: Boolean = false,
    val savedMessage: String? = null,
)

@HiltViewModel
class ManualAnalysisViewModel @Inject constructor(
    savedState: SavedStateHandle,
    contextProvider: AnalysisContextProvider,
    private val analyzer: OfferAnalyzer,
    private val offers: OfferRepository,
    private val trips: TripRepository,
) : ViewModel() {

    private fun arg(name: String) = savedState.get<String>(name)?.toDoubleOrNull()

    private val inputs = MutableStateFlow(
        ManualInputs(
            fare = formatInput(arg("fare")),
            pickupKm = formatInput(arg("pk")),
            tripKm = formatInput(arg("tk")),
            pickupMin = formatInput(arg("pm")),
            tripMin = formatInput(arg("tm")),
        ),
    )
    private val message = MutableStateFlow<String?>(null)
    private var lastContext = AnalysisContext()

    val state: StateFlow<ManualUiState> = combine(inputs, contextProvider.context, message) { i, ctx, msg ->
        lastContext = ctx
        ManualUiState(
            inputs = i,
            analysis = if (i.isEmpty) null else analyzer.analyzeManual(i.toOffer(), ctx),
            hasVehicle = ctx.vehicleId != null,
            savedMessage = msg,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ManualUiState(inputs = inputs.value))

    fun update(transform: (ManualInputs) -> ManualInputs) {
        inputs.update(transform)
        message.value = null
    }

    fun clear() {
        inputs.value = ManualInputs()
        message.value = null
    }

    /** Guarda como OFERTA ANALISADA (não conta como corrida realizada). */
    fun saveAsOffer() {
        val a = state.value.analysis ?: return
        viewModelScope.launch {
            val id = offers.record(a, lastContext.vehicleId)
            message.value = if (id == null) "Preencha valor e distâncias para salvar." else "Oferta salva no histórico."
        }
    }

    /** Registra como CORRIDA REALIZADA — ação explícita do motorista. */
    fun registerTrip() {
        val a = state.value.analysis ?: return
        if (a.offer.fare == null) {
            message.value = "Informe ao menos o valor da corrida."
            return
        }
        viewModelScope.launch {
            trips.save(Trip.fromAnalysis(a, System.currentTimeMillis(), lastContext.vehicleId))
            message.value = "Corrida registrada."
        }
    }
}
