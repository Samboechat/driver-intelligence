package com.driverintelligence.features.vehicles

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.VehicleRepository
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTextField
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.NumberField
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.designsystem.Tag
import com.driverintelligence.domain.model.ConsumptionMode
import com.driverintelligence.domain.model.CostItem
import com.driverintelligence.domain.model.CostSource
import com.driverintelligence.domain.model.CustomCost
import com.driverintelligence.domain.model.EnergyType
import com.driverintelligence.domain.model.Vehicle
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.formatInput
import com.driverintelligence.features.common.parseInput
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class CostField(val label: String, val hint: String, val totalLabel: String, val durationLabel: String) {
    MAINTENANCE("Manutenção", "Revisões e reparos", "Gasto com manutenção (R$)", "Em quantos km"),
    TIRES("Pneus", "Jogo de pneus", "Preço do jogo (R$)", "Durabilidade (km)"),
    OIL("Óleo", "Troca de óleo e filtros", "Custo da troca (R$)", "Intervalo entre trocas (km)"),
    DEPRECIATION("Depreciação", "Perda de valor do veículo", "Perda de valor estimada (R$)", "Km rodados no período"),
}

data class CostInput(val text: String = "", val source: CostSource = CostSource.NOT_SET)
data class CustomCostInput(val label: String = "", val perKm: String = "")

data class VehicleForm(
    val id: Long = 0,
    val isActive: Boolean = false,
    val name: String = "",
    val brand: String = "",
    val model: String = "",
    val year: String = "",
    val energyType: EnergyType = EnergyType.FLEX,
    val consumptionCity: String = "",
    val consumptionHighway: String = "",
    val consumptionCustom: String = "",
    val consumptionMode: ConsumptionMode = ConsumptionMode.CITY,
    val energyPrice: String = "",
    val costs: Map<CostField, CostInput> = emptyMap(),
    val custom: List<CustomCostInput> = emptyList(),
    val opOverride: String = "",
    val opIncludesFuel: Boolean = false,
    val error: String? = null,
    val done: Boolean = false,
) {
    fun cost(f: CostField) = costs[f] ?: CostInput()

    fun toVehicle(): Vehicle {
        fun item(f: CostField): CostItem {
            val c = cost(f)
            val v = parseInput(c.text)
            return CostItem(v, if (v == null) CostSource.NOT_SET else if (c.source == CostSource.NOT_SET) CostSource.CONFIGURED else c.source)
        }
        return Vehicle(
            id = id,
            name = name.trim(),
            brand = brand.trim().ifBlank { null },
            model = model.trim().ifBlank { null },
            year = year.trim().toIntOrNull(),
            energyType = energyType,
            consumptionCity = parseInput(consumptionCity),
            consumptionHighway = parseInput(consumptionHighway),
            consumptionCustom = parseInput(consumptionCustom),
            consumptionMode = consumptionMode,
            energyPrice = parseInput(energyPrice),
            maintenance = item(CostField.MAINTENANCE),
            tires = item(CostField.TIRES),
            oil = item(CostField.OIL),
            depreciation = item(CostField.DEPRECIATION),
            customCosts = custom.mapNotNull { cc -> parseInput(cc.perKm)?.let { CustomCost(label = cc.label.trim(), perKm = it) } }
                .filter { it.label.isNotBlank() },
            operationalCostPerKmOverride = parseInput(opOverride),
            operationalCostIncludesFuel = opIncludesFuel,
            isActive = isActive,
        )
    }

    companion object {
        fun from(v: Vehicle) = VehicleForm(
            id = v.id,
            isActive = v.isActive,
            name = v.name,
            brand = v.brand.orEmpty(),
            model = v.model.orEmpty(),
            year = v.year?.toString().orEmpty(),
            energyType = v.energyType,
            consumptionCity = formatInput(v.consumptionCity),
            consumptionHighway = formatInput(v.consumptionHighway),
            consumptionCustom = formatInput(v.consumptionCustom),
            consumptionMode = v.consumptionMode,
            energyPrice = formatInput(v.energyPrice),
            costs = mapOf(
                CostField.MAINTENANCE to CostInput(perKmText(v.maintenance.perKm), v.maintenance.source),
                CostField.TIRES to CostInput(perKmText(v.tires.perKm), v.tires.source),
                CostField.OIL to CostInput(perKmText(v.oil.perKm), v.oil.source),
                CostField.DEPRECIATION to CostInput(perKmText(v.depreciation.perKm), v.depreciation.source),
            ),
            custom = v.customCosts.map { CustomCostInput(it.label, perKmText(it.perKm)) },
            opOverride = perKmText(v.operationalCostPerKmOverride),
            opIncludesFuel = v.operationalCostIncludesFuel,
        )

        /** Custos por km precisam de mais casas (ex.: 0,035). */
        fun perKmText(d: Double?): String =
            if (d == null) "" else String.format(Br.locale, "%.4f", d).trimEnd('0').trimEnd(',')
    }
}

@HiltViewModel
class VehicleEditViewModel @Inject constructor(
    savedState: SavedStateHandle,
    private val repo: VehicleRepository,
) : ViewModel() {
    private val id: Long = savedState.get<Long>("id") ?: 0L
    private val _form = MutableStateFlow(VehicleForm())
    val form: StateFlow<VehicleForm> = _form.asStateFlow()

    init {
        if (id != 0L) viewModelScope.launch { repo.get(id)?.let { _form.value = VehicleForm.from(it) } }
    }

    fun update(transform: (VehicleForm) -> VehicleForm) = _form.update { transform(it).copy(error = null) }

    fun setCost(field: CostField, text: String, source: CostSource) = update { it.copy(costs = it.costs + (field to CostInput(text, source))) }

    fun save() {
        val f = _form.value
        if (f.name.isBlank()) return _form.update { it.copy(error = "Dê um nome ao veículo (ex.: \"Onix 2022\").") }
        val v = f.toVehicle()
        v.effectiveConsumption?.let { if (it <= 0) return _form.update { s -> s.copy(error = "Consumo deve ser maior que zero.") } }
        viewModelScope.launch {
            repo.save(v)
            _form.update { it.copy(done = true) }
        }
    }

    fun delete() {
        if (id == 0L) return
        viewModelScope.launch {
            repo.delete(id)
            _form.update { it.copy(done = true) }
        }
    }
}

@Composable
fun VehicleEditScreen(onBack: () -> Unit, vm: VehicleEditViewModel = hiltViewModel()) {
    val f by vm.form.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    var calculator by remember { mutableStateOf<CostField?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(f.done) { if (f.done) onBack() }

    val unit = f.energyType.consumptionUnit
    ScreenList(title = if (f.id == 0L) "Novo veículo" else "Editar veículo", onBack = onBack) {
        item {
            Section("Identificação") {
                DiTextField("Nome", f.name, { v -> vm.update { it.copy(name = v) } })
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    DiTextField("Marca", f.brand, { v -> vm.update { it.copy(brand = v) } }, Modifier.weight(1f))
                    DiTextField("Modelo", f.model, { v -> vm.update { it.copy(model = v) } }, Modifier.weight(1f))
                }
                Spacer(Modifier.height(8.dp))
                NumberField("Ano", f.year, { v -> vm.update { it.copy(year = v.take(4)) } }, integer = true)
            }
        }
        item {
            Section("Combustível e consumo", "Obrigatório para estimar o lucro.") {
                ChipRow(EnergyType.entries, f.energyType, { it.label }) { t -> vm.update { it.copy(energyType = t) } }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Urbano", f.consumptionCity, { v -> vm.update { it.copy(consumptionCity = v) } }, Modifier.weight(1f), suffix = unit)
                    NumberField("Rodoviário", f.consumptionHighway, { v -> vm.update { it.copy(consumptionHighway = v) } }, Modifier.weight(1f), suffix = unit)
                }
                Spacer(Modifier.height(8.dp))
                NumberField("Consumo médio personalizado", f.consumptionCustom, { v -> vm.update { it.copy(consumptionCustom = v) } }, suffix = unit)
                Spacer(Modifier.height(10.dp))
                Text("Consumo usado nos cálculos", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Spacer(Modifier.height(6.dp))
                ChipRow(ConsumptionMode.entries, f.consumptionMode, { it.label }) { m -> vm.update { it.copy(consumptionMode = m) } }
                val preview = f.toVehicle()
                if (preview.consumptionFallbackUsed) {
                    Spacer(Modifier.height(6.dp))
                    Text("O modo escolhido não foi preenchido; usando ${Br.decimal(preview.effectiveConsumption, 1)} $unit.", style = MaterialTheme.typography.bodySmall, color = c.warning)
                }
                Spacer(Modifier.height(8.dp))
                NumberField("Preço do combustível", f.energyPrice, { v -> vm.update { it.copy(energyPrice = v) } }, suffix = f.energyType.priceUnit)
            }
        }
        item {
            Section("Custos por km (opcionais)", "Sem eles, o lucro é marcado como estimativa parcial.") {
                CostField.entries.forEach { field ->
                    val ci = f.cost(field)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        NumberField(field.label, ci.text, { v -> vm.setCost(field, v, CostSource.CONFIGURED) }, Modifier.weight(1f), suffix = "R$/km", supporting = field.hint)
                        Spacer(Modifier.width(8.dp))
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            TextButton(onClick = { calculator = field }) { Text("Calcular") }
                            when {
                                ci.text.isBlank() -> Tag("VAZIO", c.textTertiary)
                                ci.source == CostSource.CALCULATED -> Tag("CALCULADO", c.brand)
                                else -> Tag("INFORMADO", c.positive)
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                }
            }
        }
        item {
            Section("Outros custos personalizados", "Ex.: lavagem, aluguel do carro, celular — em R$ por km.") {
                f.custom.forEachIndexed { idx, cc ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        DiTextField("Descrição", cc.label, { v -> vm.update { s -> s.copy(custom = s.custom.toMutableList().also { it[idx] = cc.copy(label = v) }) } }, Modifier.weight(1.3f))
                        Spacer(Modifier.width(8.dp))
                        NumberField("R$/km", cc.perKm, { v -> vm.update { s -> s.copy(custom = s.custom.toMutableList().also { it[idx] = cc.copy(perKm = v) }) } }, Modifier.weight(1f))
                        IconButton(onClick = { vm.update { s -> s.copy(custom = s.custom.toMutableList().also { it.removeAt(idx) }) } }) {
                            Icon(Icons.Default.Close, contentDescription = "Remover", tint = c.textTertiary)
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                }
                SecondaryButton("Adicionar custo", { vm.update { it.copy(custom = it.custom + CustomCostInput()) } }, Modifier.fillMaxWidth())
            }
        }
        item {
            Section("Custo operacional único (avançado)", "Se você já sabe seu custo total por km, informe aqui. Ele substitui a soma dos itens acima.") {
                NumberField("Custo operacional", f.opOverride, { v -> vm.update { it.copy(opOverride = v) } }, suffix = "R$/km")
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Esse valor já inclui combustível", style = MaterialTheme.typography.bodyMedium, color = c.textPrimary)
                        Text("Evita descontar o combustível duas vezes.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                    }
                    Switch(
                        checked = f.opIncludesFuel,
                        onCheckedChange = { v -> vm.update { it.copy(opIncludesFuel = v) } },
                        enabled = f.opOverride.isNotBlank(),
                        colors = SwitchDefaults.colors(checkedTrackColor = c.brand),
                    )
                }
            }
        }
        item {
            val v = f.toVehicle()
            val (cpk, partial) = costPerKmPreview(v)
            DiCard {
                Text("Resultado", style = MaterialTheme.typography.titleSmall, color = c.textSecondary)
                InfoRow("Custo por km considerado", Br.perKm(cpk), emphasize = true)
                InfoRow("Situação", if (partial) "estimativa parcial" else "custos completos", valueColor = if (partial) c.warning else c.positive)
            }
        }
        f.error?.let { e -> item { Banner(e, c.negative) } }
        item { PrimaryButton("Salvar veículo", vm::save, Modifier.fillMaxWidth()) }
        if (f.id != 0L) item { SecondaryButton("Excluir veículo", { confirmDelete = true }, Modifier.fillMaxWidth(), color = c.negative) }
    }

    calculator?.let { field ->
        CostCalculatorDialog(field, onDismiss = { calculator = null }) { perKm ->
            vm.setCost(field, VehicleForm.perKmText(perKm), CostSource.CALCULATED)
            calculator = null
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Excluir veículo?") },
            text = { Text("As corridas já registradas continuam no histórico.") },
            confirmButton = { TextButton(onClick = { confirmDelete = false; vm.delete() }) { Text("Excluir", color = c.negative) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancelar") } },
            containerColor = c.surfaceRaised,
        )
    }
}

@Composable
private fun CostCalculatorDialog(field: CostField, onDismiss: () -> Unit, onApply: (Double) -> Unit) {
    var total by remember { mutableStateOf("") }
    var km by remember { mutableStateOf("") }
    val result = Vehicle.perKmFrom(parseInput(total), parseInput(km))
    val c = DiTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Calcular ${field.label.lowercase()} por km") },
        text = {
            Column {
                NumberField(field.totalLabel, total, { total = it })
                Spacer(Modifier.height(8.dp))
                NumberField(field.durationLabel, km, { km = it }, suffix = "km")
                Spacer(Modifier.height(10.dp))
                Text(
                    result?.let { "= ${Br.money(it).replace("R$ ", "R$ ")} por km (${VehicleForm.perKmText(it)})" } ?: "Informe os dois valores.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (result != null) c.textPrimary else c.textTertiary,
                )
                Text("O resultado fica marcado como \"calculado\" a partir dos seus dados.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
            }
        },
        confirmButton = { TextButton(enabled = result != null, onClick = { result?.let(onApply) }) { Text("Usar") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } },
        containerColor = c.surfaceRaised,
    )
}

@Composable
private fun Section(title: String, subtitle: String? = null, content: @Composable () -> Unit) {
    val c = DiTheme.colors
    DiCard {
        Text(title, style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
        if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        Spacer(Modifier.height(12.dp))
        content()
    }
}

@Composable
private fun <T> ChipRow(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    val c = DiTheme.colors
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { o ->
            FilterChip(
                selected = o == selected,
                onClick = { onSelect(o) },
                label = { Text(label(o)) },
                colors = androidx.compose.material3.FilterChipDefaults.filterChipColors(
                    containerColor = c.surfaceSunken,
                    labelColor = c.textSecondary,
                    selectedContainerColor = c.brandSoft,
                    selectedLabelColor = c.textPrimary,
                ),
            )
        }
    }
}
