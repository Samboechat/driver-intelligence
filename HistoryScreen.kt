package com.driverintelligence.features.history

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.R
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTextField
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.EmptyState
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.SegmentedSelector
import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.OfferRow
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.TripRow
import com.driverintelligence.features.common.fullDateTime
import java.time.LocalDate

@Composable
fun HistoryScreen(onEditTrip: (Long) -> Unit, onNewTrip: () -> Unit, vm: HistoryViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    val f = state.filters
    val context = LocalContext.current
    var sortMenu by remember { mutableStateOf(false) }
    var selectedOffer by remember { mutableStateOf<AnalyzedOffer?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        if (uri != null) vm.exportCsv(context.contentResolver, uri)
    }

    ScreenList(
        title = "Histórico",
        actions = {
            if (f.tab == HistoryTab.TRIPS) {
                IconButton(onClick = { exportLauncher.launch("corridas-${LocalDate.now()}.csv") }) {
                    Icon(painterResource(R.drawable.ic_download), contentDescription = "Exportar CSV", tint = c.textSecondary)
                }
                IconButton(onClick = onNewTrip) {
                    Icon(Icons.Default.Add, contentDescription = "Registrar corrida", tint = c.textSecondary)
                }
            }
        },
    ) {
        item {
            SegmentedSelector(HistoryTab.entries, f.tab, { it.label }, { t -> vm.setFilters { it.copy(tab = t) } })
        }
        item {
            DiTextField("Buscar (categoria, endereço, valor)", f.query, { q -> vm.setFilters { it.copy(query = q) } })
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PeriodFilter.entries.forEach { p ->
                    Chip(p.label, f.period == p) { vm.setFilters { it.copy(period = p) } }
                }
                Spacer(Modifier.width(4.dp))
                Box {
                    Chip("Ordenar: ${f.sort.label}", false) { sortMenu = true }
                    DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                        SortOrder.entries.forEach { s ->
                            DropdownMenuItem(text = { Text(s.label) }, onClick = {
                                vm.setFilters { it.copy(sort = s) }
                                sortMenu = false
                            })
                        }
                    }
                }
            }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("Todas", f.classification == null) { vm.setFilters { it.copy(classification = null) } }
                Classification.entries.forEach { cl ->
                    Chip(cl.label, f.classification == cl) { vm.setFilters { it.copy(classification = if (it.classification == cl) null else cl) } }
                }
                Chip("Leitura automática", f.source == DataSource.OCR) { vm.setFilters { it.copy(source = if (it.source == DataSource.OCR) null else DataSource.OCR) } }
                Chip("Manual", f.source == DataSource.MANUAL) { vm.setFilters { it.copy(source = if (it.source == DataSource.MANUAL) null else DataSource.MANUAL) } }
            }
        }
        state.message?.let { m -> item { Banner(m, c.positive, action = "OK", onAction = vm::dismissMessage) } }

        if (f.tab == HistoryTab.TRIPS) {
            item {
                val s = state.summary
                DiCard {
                    Text("Relatório do período", style = MaterialTheme.typography.titleSmall, color = c.textSecondary)
                    InfoRow("Corridas", s.count.toString())
                    InfoRow("Faturamento", Br.money(s.revenue), emphasize = true)
                    InfoRow("Lucro operacional estimado", Br.money(s.profit), valueColor = s.profit?.let { if (it >= 0) c.positive else c.negative })
                    InfoRow("Distância", Br.km(s.km))
                    InfoRow("Média por km", Br.perKm(s.perKm))
                }
            }
            if (state.trips.isEmpty()) {
                item { DiCard { EmptyState("Nenhuma corrida no filtro", "Registre corridas pelo overlay (\"Aceitei\"), pela análise manual ou pelo botão +.", actionLabel = "Registrar corrida", onAction = onNewTrip) } }
            } else {
                items(state.trips, key = { "t${it.id}" }) { t -> TripRow(t, onClick = { onEditTrip(t.id) }) }
            }
        } else {
            item {
                Text(
                    "Ofertas vistas e analisadas. Não entram no faturamento — registre como corrida apenas as que você aceitou.",
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textTertiary,
                )
            }
            if (state.offers.isEmpty()) {
                item { DiCard { EmptyState("Nenhuma oferta no filtro", "As ofertas lidas pelo assistente aparecem aqui.") } }
            } else {
                items(state.offers, key = { "o${it.id}" }) { o -> OfferRow(o, onClick = { selectedOffer = o }) }
            }
        }
    }

    selectedOffer?.let { o ->
        AlertDialog(
            onDismissRequest = { selectedOffer = null },
            title = { Text("${Br.money(o.fare)} · ${o.classification.label}") },
            text = {
                androidx.compose.foundation.layout.Column {
                    Text(o.headline, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
                    InfoRow("Detectada em", fullDateTime(o.detectedAt))
                    InfoRow("Distância total", Br.km(o.totalKm))
                    InfoRow("Tempo total", Br.minutes(o.totalMin))
                    InfoRow("R$/km · R$/h", "${Br.decimal(o.revenuePerKm)} · ${Br.decimal(o.revenuePerHour, 0)}")
                    InfoRow("Lucro estimado", Br.money(o.estimatedProfit))
                    InfoRow("Confiança", Br.percent(o.confidence))
                    InfoRow("Origem", o.source.label)
                }
            },
            confirmButton = {
                if (!o.isRegistered && o.fare != null) {
                    TextButton(onClick = {
                        vm.registerOffer(o)
                        selectedOffer = null
                    }) { Text("Registrar como realizada") }
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    vm.deleteOffer(o.id)
                    selectedOffer = null
                }) { Text("Excluir", color = c.negative) }
            },
            containerColor = c.surfaceRaised,
        )
    }
}

@Composable
private fun Chip(label: String, selected: Boolean, onClick: () -> Unit) {
    val c = DiTheme.colors
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            containerColor = c.surface,
            labelColor = c.textSecondary,
            selectedContainerColor = c.brandSoft,
            selectedLabelColor = c.textPrimary,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = c.outline,
            selectedBorderColor = c.brand.copy(alpha = 0.5f),
        ),
    )
}
