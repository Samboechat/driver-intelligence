package com.driverintelligence.features.manual

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.NumberField
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.features.common.AnalysisCard
import com.driverintelligence.features.common.ScreenList

@Composable
fun ManualAnalysisScreen(onBack: () -> Unit, onOpenTrips: () -> Unit, vm: ManualAnalysisViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    val i = state.inputs

    ScreenList(title = "Analisar oferta", subtitle = "Inserção manual — mesmo motor do overlay", onBack = onBack) {
        item {
            DiCard {
                Text("Dados da oferta", style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
                Spacer(Modifier.height(10.dp))
                NumberField("Valor da corrida", i.fare, { v -> vm.update { it.copy(fare = v) } }, suffix = "R$")
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Até o passageiro", i.pickupKm, { v -> vm.update { it.copy(pickupKm = v) } }, Modifier.weight(1f), suffix = "km")
                    NumberField("Tempo", i.pickupMin, { v -> vm.update { it.copy(pickupMin = v) } }, Modifier.weight(1f), suffix = "min")
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Viagem", i.tripKm, { v -> vm.update { it.copy(tripKm = v) } }, Modifier.weight(1f), suffix = "km")
                    NumberField("Tempo", i.tripMin, { v -> vm.update { it.copy(tripMin = v) } }, Modifier.weight(1f), suffix = "min")
                }
            }
        }
        if (!state.hasVehicle) {
            item { Banner("Sem veículo cadastrado: o lucro não pode ser estimado.", c.warning) }
        }
        state.analysis?.let { a -> item { AnalysisCard(a) } }
        state.savedMessage?.let { msg -> item { Banner(msg, c.positive, action = "Ver histórico", onAction = onOpenTrips) } }
        if (state.analysis != null) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SecondaryButton("Salvar oferta", vm::saveAsOffer, Modifier.weight(1f))
                    PrimaryButton("Registrar corrida", vm::registerTrip, Modifier.weight(1f))
                }
            }
            item { SecondaryButton("Limpar", vm::clear, Modifier.fillMaxWidth()) }
        }
    }
}
