package com.driverintelligence.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.NumberField
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.domain.model.Goals
import com.driverintelligence.domain.model.Metric
import com.driverintelligence.domain.model.ScoringConfig
import com.driverintelligence.domain.model.ScoringWeights
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.formatInput
import com.driverintelligence.features.common.parseInput
import kotlin.math.roundToInt

@Composable
fun GoalsScreen(onBack: () -> Unit, vm: SettingsViewModel = hiltViewModel()) {
    val settings by vm.settings.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val s = settings ?: return
    val c = DiTheme.colors
    val g = s.goals

    var daily by remember { mutableStateOf(formatInput(g.dailyRevenue)) }
    var dailyProfit by remember { mutableStateOf(formatInput(g.dailyProfit)) }
    var weekly by remember { mutableStateOf(formatInput(g.weeklyRevenue)) }
    var monthly by remember { mutableStateOf(formatInput(g.monthlyRevenue)) }
    var maxHours by remember { mutableStateOf(formatInput(g.maxDailyHours)) }
    var minKm by remember { mutableStateOf(formatInput(g.minRevenuePerKm)) }
    var minHour by remember { mutableStateOf(formatInput(g.minRevenuePerHour)) }
    var minProfitKm by remember { mutableStateOf(formatInput(g.minProfitPerKm)) }
    var minProfitHour by remember { mutableStateOf(formatInput(g.minProfitPerHour)) }
    var minProfitTrip by remember { mutableStateOf(formatInput(g.minProfitPerTrip)) }
    var maxPickup by remember { mutableStateOf(formatInput(g.maxPickupMinutes)) }
    var maxUnproductive by remember { mutableStateOf(formatInput(g.maxUnproductiveShare * 100)) }
    var maxCost by remember { mutableStateOf(formatInput(g.maxCostShare * 100)) }
    var maxTotal by remember { mutableStateOf(formatInput(g.maxTotalDistanceKm)) }

    ScreenList(title = "Metas e limites", subtitle = "Valores iniciais são só ponto de partida — ajuste à sua realidade", onBack = onBack) {
        item {
            Group("Metas de faturamento") {
                NumberField("Meta diária de faturamento", daily, { daily = it }, suffix = "R$")
                NumberField("Meta diária de lucro", dailyProfit, { dailyProfit = it }, suffix = "R$")
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Meta semanal", weekly, { weekly = it }, Modifier.weight(1f), suffix = "R$")
                    NumberField("Meta mensal", monthly, { monthly = it }, Modifier.weight(1f), suffix = "R$")
                }
                NumberField("Limite de horas por dia", maxHours, { maxHours = it }, suffix = "h")
            }
        }
        item {
            Group("Mínimos por corrida", "Usados na classificação das ofertas.") {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Valor mínimo por km", minKm, { minKm = it }, Modifier.weight(1f), suffix = "R$")
                    NumberField("Valor mínimo por hora", minHour, { minHour = it }, Modifier.weight(1f), suffix = "R$")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NumberField("Lucro mínimo por km", minProfitKm, { minProfitKm = it }, Modifier.weight(1f), suffix = "R$")
                    NumberField("Lucro mínimo por hora", minProfitHour, { minProfitHour = it }, Modifier.weight(1f), suffix = "R$")
                }
                NumberField("Lucro mínimo por corrida (opcional)", minProfitTrip, { minProfitTrip = it }, suffix = "R$")
            }
        }
        item {
            Group("Limites de deslocamento e custo") {
                NumberField("Tempo máximo até o passageiro", maxPickup, { maxPickup = it }, suffix = "min")
                NumberField("Distância de busca máxima (% do total)", maxUnproductive, { maxUnproductive = it }, suffix = "%")
                NumberField("Custo máximo (% do valor)", maxCost, { maxCost = it }, suffix = "%")
                NumberField("Distância total máxima (opcional)", maxTotal, { maxTotal = it }, suffix = "km")
            }
        }
        message?.let { m -> item { Banner(m, c.positive) } }
        item {
            PrimaryButton(
                "Salvar metas",
                {
                    val d = Goals()
                    vm.saveGoals(
                        Goals(
                            dailyRevenue = parseInput(daily),
                            dailyProfit = parseInput(dailyProfit),
                            weeklyRevenue = parseInput(weekly),
                            monthlyRevenue = parseInput(monthly),
                            maxDailyHours = parseInput(maxHours),
                            minRevenuePerKm = parseInput(minKm) ?: d.minRevenuePerKm,
                            minRevenuePerHour = parseInput(minHour) ?: d.minRevenuePerHour,
                            minProfitPerKm = parseInput(minProfitKm) ?: d.minProfitPerKm,
                            minProfitPerHour = parseInput(minProfitHour) ?: d.minProfitPerHour,
                            minProfitPerTrip = parseInput(minProfitTrip),
                            maxPickupMinutes = parseInput(maxPickup) ?: d.maxPickupMinutes,
                            maxUnproductiveShare = parseInput(maxUnproductive)?.div(100) ?: d.maxUnproductiveShare,
                            maxCostShare = parseInput(maxCost)?.div(100) ?: d.maxCostShare,
                            maxTotalDistanceKm = parseInput(maxTotal),
                        ),
                    )
                },
                Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
fun ScoringScreen(onBack: () -> Unit, vm: SettingsViewModel = hiltViewModel()) {
    val settings by vm.settings.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val s = settings ?: return
    val c = DiTheme.colors

    var weights by remember { mutableStateOf(s.scoring.weights) }
    var green by remember { mutableStateOf(s.scoring.greenThreshold.toFloat()) }
    var yellow by remember { mutableStateOf(s.scoring.yellowThreshold.toFloat()) }
    var confidence by remember { mutableStateOf(s.scoring.minRecognitionConfidence.toFloat()) }

    val total = Metric.entries.sumOf { weights.weightOf(it) }.takeIf { it > 0 } ?: 1.0

    ScreenList(title = "Critérios de classificação", subtitle = "Nenhum indicador decide sozinho", onBack = onBack) {
        item {
            Group("Pesos dos indicadores", "A nota final é a média ponderada; os pesos são normalizados.") {
                Metric.entries.forEach { m ->
                    val w = weights.weightOf(m)
                    Text("${m.label}: ${(w / total * 100).roundToInt()}%", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                    Slider(
                        value = w.toFloat(),
                        onValueChange = { v -> weights = weights.with(m, v.toDouble()) },
                        valueRange = 0f..1f,
                        colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                    )
                }
            }
        }
        item {
            Group("Limites de cor", "Nota de 0 a 100. Cumprir exatamente a meta vale 70.") {
                Text("Verde a partir de ${(green * 100).roundToInt()}", style = MaterialTheme.typography.labelMedium, color = c.positive)
                Slider(green, { green = it.coerceAtLeast(yellow + 0.05f) }, valueRange = 0.3f..0.95f, colors = SliderDefaults.colors(thumbColor = c.positive, activeTrackColor = c.positive))
                Text("Amarelo a partir de ${(yellow * 100).roundToInt()}", style = MaterialTheme.typography.labelMedium, color = c.warning)
                Slider(yellow, { yellow = it.coerceAtMost(green - 0.05f) }, valueRange = 0.1f..0.9f, colors = SliderDefaults.colors(thumbColor = c.warning, activeTrackColor = c.warning))
                Text("Abaixo disso: vermelho.", style = MaterialTheme.typography.bodySmall, color = c.negative)
            }
        }
        item {
            Group("Confiança mínima da leitura", "Abaixo dela, o overlay mostra \"dados insuficientes\" em vez de recomendar.") {
                Text("${(confidence * 100).roundToInt()}%", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Slider(confidence, { confidence = it }, valueRange = 0.3f..0.95f, colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand))
            }
        }
        message?.let { m -> item { Banner(m, c.positive) } }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton("Restaurar padrão", {
                    val d = ScoringConfig()
                    weights = d.weights
                    green = d.greenThreshold.toFloat()
                    yellow = d.yellowThreshold.toFloat()
                    confidence = d.minRecognitionConfidence.toFloat()
                }, Modifier.weight(1f))
                PrimaryButton("Salvar", {
                    vm.saveScoring(ScoringConfig(weights, green.toDouble(), yellow.toDouble(), confidence.toDouble()))
                }, Modifier.weight(1f))
            }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

private fun ScoringWeights.with(m: Metric, v: Double): ScoringWeights = when (m) {
    Metric.REVENUE_PER_KM -> copy(revenuePerKm = v)
    Metric.PROFIT_PER_KM -> copy(profitPerKm = v)
    Metric.REVENUE_PER_HOUR -> copy(revenuePerHour = v)
    Metric.PROFIT_PER_HOUR -> copy(profitPerHour = v)
    Metric.PICKUP_TIME -> copy(pickupTime = v)
    Metric.UNPRODUCTIVE_DISTANCE -> copy(unproductiveDistance = v)
    Metric.COST_SHARE -> copy(costShare = v)
}
