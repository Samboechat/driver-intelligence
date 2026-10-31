package com.driverintelligence.features.vehicles

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.VehicleRepository
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.EmptyState
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.designsystem.Tag
import com.driverintelligence.domain.financial.FinancialEngine
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.Vehicle
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.ScreenList
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class VehiclesViewModel @Inject constructor(private val repo: VehicleRepository) : ViewModel() {
    val vehicles: StateFlow<List<Vehicle>?> = repo.vehicles.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
    fun setActive(id: Long) = viewModelScope.launch { repo.setActive(id) }
}

/** Custo por km resultante do perfil (1 km de viagem, sem busca), para exibição. */
fun costPerKmPreview(v: Vehicle): Pair<Double?, Boolean> {
    val r = FinancialEngine().calculate(OfferData(fare = 1.0, pickupDistanceKm = 0.0, tripDistanceKm = 1.0), v.toCostProfile())
    return r.costPerKm to r.isCostEstimatePartial
}

@Composable
fun VehiclesScreen(onEdit: (Long) -> Unit, onAdd: () -> Unit, vm: VehiclesViewModel = hiltViewModel()) {
    val list by vm.vehicles.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    ScreenList(
        title = "Veículos",
        actions = { IconButton(onClick = onAdd) { Icon(Icons.Default.Add, contentDescription = "Adicionar veículo", tint = c.textSecondary) } },
    ) {
        val vehicles = list ?: return@ScreenList
        if (vehicles.isEmpty()) {
            item {
                DiCard {
                    EmptyState(
                        "Nenhum veículo",
                        "Cadastre consumo e preço do combustível para estimar o lucro. Os demais custos são opcionais.",
                        actionLabel = "Cadastrar veículo",
                        onAction = onAdd,
                    )
                }
            }
        }
        items(vehicles, key = { it.id }) { v ->
            val (cpk, partial) = costPerKmPreview(v)
            DiCard(onClick = { onEdit(v.id) }, borderColor = if (v.isActive) c.brand.copy(alpha = 0.5f) else null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(v.name, style = MaterialTheme.typography.titleMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
                    if (v.isActive) Tag("ATIVO", c.brand)
                }
                Text(v.displayName.takeIf { it != v.name } ?: v.energyType.label, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
                Spacer(Modifier.height(8.dp))
                InfoRow("Consumo", v.effectiveConsumption?.let { "${Br.decimal(it, 1)} ${v.energyType.consumptionUnit}" } ?: "não informado")
                InfoRow("Preço do combustível", v.energyPrice?.let { "${Br.money(it)} ${v.energyType.priceUnit.removePrefix("R$")}" } ?: "não informado")
                InfoRow("Custo por km", Br.perKm(cpk), note = if (partial) "parcial — há custos não configurados" else "todos os custos configurados")
                if (!v.isActive) {
                    Spacer(Modifier.height(8.dp))
                    SecondaryButton("Usar este veículo", { vm.setActive(v.id) }, Modifier.fillMaxWidth())
                }
            }
        }
        if (vehicles.isNotEmpty()) {
            item {
                Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                    Text("O veículo ativo é usado nas análises do overlay.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                }
            }
        }
    }
}
