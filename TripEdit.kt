package com.driverintelligence.features.history

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.AnalysisContextProvider
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTextField
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.NumberField
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.formatInput
import com.driverintelligence.features.common.fullDateTime
import com.driverintelligence.features.common.parseFullDateTime
import com.driverintelligence.features.common.parseInput
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TripForm(
    val id: Long = 0,
    val original: Trip? = null,
    val dateTime: String = fullDateTime(System.currentTimeMillis()),
    val fare: String = "",
    val pickupKm: String = "",
    val pickupMin: String = "",
    val tripKm: String = "",
    val tripMin: String = "",
    val category: String = "",
    val origin: String = "",
    val destination: String = "",
    val notes: String = "",
    val error: String? = null,
    val done: Boolean = false,
    val loaded: Boolean = false,
)

@HiltViewModel
class TripEditViewModel @Inject constructor(
    savedState: SavedStateHandle,
    private val trips: TripRepository,
    private val contextProvider: AnalysisContextProvider,
) : ViewModel() {
    private val id: Long = savedState.get<Long>("id") ?: 0L
    private val _form = MutableStateFlow(TripForm(id = id, loaded = id == 0L))
    val form: StateFlow<TripForm> = _form.asStateFlow()

    init {
        if (id != 0L) viewModelScope.launch {
            val t = trips.get(id)
            _form.value = if (t == null) TripForm(error = "Corrida não encontrada.", loaded = true) else TripForm(
                id = t.id,
                original = t,
                dateTime = fullDateTime(t.startedAt),
                fare = formatInput(t.fare),
                pickupKm = formatInput(t.pickupKm),
                pickupMin = formatInput(t.pickupMin),
                tripKm = formatInput(t.tripKm),
                tripMin = formatInput(t.tripMin),
                category = t.category.orEmpty(),
                origin = t.origin.orEmpty(),
                destination = t.destination.orEmpty(),
                notes = t.notes.orEmpty(),
                loaded = true,
            )
        }
    }

    fun update(transform: (TripForm) -> TripForm) = _form.update { transform(it).copy(error = null) }

    fun save() {
        val f = _form.value
        val fare = parseInput(f.fare)
        val start = parseFullDateTime(f.dateTime)
        when {
            fare == null || fare <= 0 -> return _form.update { it.copy(error = "Informe o valor da corrida.") }
            start == null -> return _form.update { it.copy(error = "Data inválida. Use o formato dd/mm/aaaa hh:mm.") }
        }
        viewModelScope.launch {
            val ctx = contextProvider.context.first()
            val base = f.original ?: Trip(startedAt = start!!, fare = fare!!, source = DataSource.MANUAL, vehicleId = ctx.vehicleId)
            val edited = base.copy(
                startedAt = start!!,
                fare = fare!!,
                pickupKm = parseInput(f.pickupKm),
                pickupMin = parseInput(f.pickupMin),
                tripKm = parseInput(f.tripKm),
                tripMin = parseInput(f.tripMin),
                category = f.category.trim().ifBlank { null },
                origin = f.origin.trim().ifBlank { null },
                destination = f.destination.trim().ifBlank { null },
                notes = f.notes.trim().ifBlank { null },
            ).recalculated(ctx)
            trips.save(edited)
            _form.update { it.copy(done = true) }
        }
    }

    fun delete() {
        if (id == 0L) return
        viewModelScope.launch {
            trips.delete(id)
            _form.update { it.copy(done = true) }
        }
    }
}

@Composable
fun TripEditScreen(onBack: () -> Unit, vm: TripEditViewModel = hiltViewModel()) {
    val f by vm.form.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(f.done) { if (f.done) onBack() }

    ScreenList(title = if (f.id == 0L) "Registrar corrida" else "Editar corrida", onBack = onBack) {
        if (!f.loaded) return@ScreenList
        item {
            DiCard {
                DiTextField("Data e hora", f.dateTime, { v -> vm.update { it.copy(dateTime = v) } }, supporting = "dd/mm/aaaa hh:mm")
                Spacer(Modifier.height(8.dp))
                NumberField("Valor recebido", f.fare, { v -> vm.update { it.copy(fare = v) } }, suffix = "R$")
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Busca", f.pickupKm, { v -> vm.update { it.copy(pickupKm = v) } }, Modifier.weight(1f), suffix = "km")
                    NumberField("Tempo", f.pickupMin, { v -> vm.update { it.copy(pickupMin = v) } }, Modifier.weight(1f), suffix = "min")
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Viagem", f.tripKm, { v -> vm.update { it.copy(tripKm = v) } }, Modifier.weight(1f), suffix = "km")
                    NumberField("Tempo", f.tripMin, { v -> vm.update { it.copy(tripMin = v) } }, Modifier.weight(1f), suffix = "min")
                }
            }
        }
        item {
            DiCard {
                DiTextField("Categoria", f.category, { v -> vm.update { it.copy(category = v) } })
                Spacer(Modifier.height(8.dp))
                DiTextField("Origem", f.origin, { v -> vm.update { it.copy(origin = v) } })
                Spacer(Modifier.height(8.dp))
                DiTextField("Destino", f.destination, { v -> vm.update { it.copy(destination = v) } })
                Spacer(Modifier.height(8.dp))
                DiTextField("Observações", f.notes, { v -> vm.update { it.copy(notes = v) } }, singleLine = false)
            }
        }
        f.original?.let { t ->
            item {
                DiCard {
                    Text("Registro", style = MaterialTheme.typography.titleSmall, color = c.textSecondary)
                    InfoRow("Origem dos dados", t.source.label)
                    t.recognitionConfidence?.let { InfoRow("Confiança da leitura", Br.percent(it)) }
                    InfoRow("Lucro estimado atual", Br.money(t.estimatedProfit), note = if (t.costPartial) "estimativa parcial" else null)
                    Text("Ao salvar, os indicadores são recalculados com os custos do veículo ativo.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                }
            }
        }
        f.error?.let { e -> item { Banner(e, c.negative) } }
        item { PrimaryButton("Salvar", vm::save, Modifier.fillMaxWidth()) }
        if (f.id != 0L) {
            item { SecondaryButton("Excluir corrida", { confirmDelete = true }, Modifier.fillMaxWidth(), color = c.negative) }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Excluir corrida?") },
            text = { Text("O registro será removido do histórico e das estatísticas.") },
            confirmButton = { TextButton(onClick = { confirmDelete = false; vm.delete() }) { Text("Excluir", color = c.negative) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancelar") } },
            containerColor = c.surfaceRaised,
        )
    }
}
