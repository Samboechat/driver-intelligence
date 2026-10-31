package com.driverintelligence.features.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.BuildConfig
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.NumberField
import com.driverintelligence.designsystem.SegmentedSelector
import com.driverintelligence.domain.model.CaptureRegion
import com.driverintelligence.domain.model.EmptyReturnScenario
import com.driverintelligence.domain.model.ThemeMode
import com.driverintelligence.domain.overlay.OverlayMode
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.formatInput
import com.driverintelligence.features.common.parseInput
import kotlin.math.roundToInt

private enum class ReturnMode(val label: String) { NONE("Não estimar"), PERCENT("% da viagem"), FIXED("Km fixos") }

@Composable
fun SettingsScreen(
    onOpenGoals: () -> Unit,
    onOpenScoring: () -> Unit,
    onOpenPermissions: () -> Unit,
    onOpenOcrLab: () -> Unit,
    onOpenPrivacy: () -> Unit,
    vm: SettingsViewModel = hiltViewModel(),
) {
    val settings by vm.settings.collectAsStateWithLifecycle()
    val assistant by vm.assistant.collectAsStateWithLifecycle()
    val s = settings ?: return
    val c = DiTheme.colors

    ScreenList(title = "Ajustes") {
        item {
            Group("Análise") {
                NavRow("Metas e limites", "Meta diária, R$/km e R$/h mínimos, lucro mínimo", onOpenGoals)
                NavRow("Critérios de classificação", "Pesos de cada indicador e limites de cor", onOpenScoring)
            }
        }
        item {
            val er = s.emptyReturn
            val mode = when (er) {
                EmptyReturnScenario.None -> ReturnMode.NONE
                is EmptyReturnScenario.PercentOfTrip -> ReturnMode.PERCENT
                is EmptyReturnScenario.FixedDistance -> ReturnMode.FIXED
            }
            var value by remember(er) {
                mutableStateOf(
                    when (er) {
                        is EmptyReturnScenario.PercentOfTrip -> formatInput(er.percent)
                        is EmptyReturnScenario.FixedDistance -> formatInput(er.km)
                        EmptyReturnScenario.None -> ""
                    },
                )
            }
            Group("Retorno vazio", "Cenário opcional, exibido separado do lucro da corrida.") {
                SegmentedSelector(ReturnMode.entries, mode, { it.label }, { m ->
                    vm.setEmptyReturn(
                        when (m) {
                            ReturnMode.NONE -> EmptyReturnScenario.None
                            ReturnMode.PERCENT -> EmptyReturnScenario.PercentOfTrip(parseInput(value)?.takeIf { mode == ReturnMode.PERCENT } ?: 50.0)
                            ReturnMode.FIXED -> EmptyReturnScenario.FixedDistance(parseInput(value)?.takeIf { mode == ReturnMode.FIXED } ?: 5.0)
                        },
                    )
                })
                if (mode != ReturnMode.NONE) {
                    Spacer(Modifier.height(8.dp))
                    NumberField(
                        if (mode == ReturnMode.PERCENT) "Percentual da distância da viagem" else "Distância de retorno",
                        value,
                        { v ->
                            value = v
                            parseInput(v)?.takeIf { it > 0 }?.let { n ->
                                vm.setEmptyReturn(if (mode == ReturnMode.PERCENT) EmptyReturnScenario.PercentOfTrip(n) else EmptyReturnScenario.FixedDistance(n))
                            }
                        },
                        suffix = if (mode == ReturnMode.PERCENT) "%" else "km",
                    )
                }
            }
        }
        item {
            val ip = s.intelligence
            Group("Inteligência de corrida", "O app aprende com suas corridas quanto os tempos das ofertas atrasam de verdade.") {
                SwitchRow("Detectar aceite, recusa e acompanhar a corrida", ip.autoTrack) { v -> vm.updateIntelligence { it.copy(autoTrack = v) } }
                SwitchRow("Registrar sozinho a corrida concluída (com tempos reais)", ip.autoRegister) { v -> vm.updateIntelligence { it.copy(autoRegister = v) } }
                SwitchRow("Classificar pelo tempo realista", ip.useRealisticTime) { v -> vm.updateIntelligence { it.copy(useRealisticTime = v) } }
                Spacer(Modifier.height(6.dp))
                Text(
                    "Estimativa padrão até ter 5 corridas medidas",
                    style = MaterialTheme.typography.labelMedium,
                    color = c.textSecondary,
                )
                Text("Busca: +${((ip.defaultPickupFactor - 1) * 100).roundToInt()}%", style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
                Slider(
                    value = ip.defaultPickupFactor.toFloat(),
                    onValueChange = { v -> vm.updateIntelligence { it.copy(defaultPickupFactor = (v * 20).roundToInt() / 20.0) } },
                    valueRange = 1f..2.5f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Text("Viagem: +${((ip.defaultTripFactor - 1) * 100).roundToInt()}%", style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
                Slider(
                    value = ip.defaultTripFactor.toFloat(),
                    onValueChange = { v -> vm.updateIntelligence { it.copy(defaultTripFactor = (v * 20).roundToInt() / 20.0) } },
                    valueRange = 1f..2f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Text(
                    "Depois disso, valem os tempos medidos, inclusive por horário (pico pesa diferente).",
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textTertiary,
                )
            }
        }
        item {
            val o = s.overlay
            Group("Janela flutuante") {
                Text("Modo inicial", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Spacer(Modifier.height(6.dp))
                SegmentedSelector(OverlayMode.entries, o.mode, { modeLabel(it) }, { m -> vm.updateOverlay { it.copy(mode = m) } })
                Spacer(Modifier.height(12.dp))
                Text("Opacidade: ${(o.opacity * 100).roundToInt()}%", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Slider(
                    value = o.opacity,
                    onValueChange = { v -> vm.updateOverlay { it.copy(opacity = v) } },
                    valueRange = 0.5f..1f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Spacer(Modifier.height(4.dp))
                Text("Tamanho da janela e do texto", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Spacer(Modifier.height(6.dp))
                SegmentedSelector(
                    TEXT_SCALES,
                    TEXT_SCALES.minByOrNull { kotlin.math.abs(it - o.textScale) } ?: 1f,
                    { scaleLabel(it) },
                    { v -> vm.updateOverlay { it.copy(textScale = v) } },
                )
                Spacer(Modifier.height(6.dp))
                SwitchRow("Vibração ao reconhecer oferta", o.haptics) { v -> vm.updateOverlay { it.copy(haptics = v) } }
                SwitchRow("Mostrar meta do dia no rodapé", o.showDailyProgress) { v -> vm.updateOverlay { it.copy(showDailyProgress = v) } }
                NavRow("Restaurar posição da janela", "Volta para o canto superior esquerdo", { vm.updateOverlay { it.copy(relX = 0.03f, relY = 0.10f) } })
            }
        }
        item {
            val cp = s.capture
            Group("Captura e desempenho", "Intervalos maiores economizam bateria; menores reagem mais rápido.") {
                Text("Intervalo com oferta ativa: ${cp.activeIntervalMs} ms", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Slider(
                    value = cp.activeIntervalMs.toFloat(),
                    onValueChange = { v -> vm.updateCapture { it.copy(activeIntervalMs = (v / 50).roundToInt() * 50L) } },
                    valueRange = 300f..1500f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Text("Intervalo em espera: ${cp.idleIntervalMs} ms", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Slider(
                    value = cp.idleIntervalMs.toFloat(),
                    onValueChange = { v -> vm.updateCapture { it.copy(idleIntervalMs = (v / 100).roundToInt() * 100L) } },
                    valueRange = 600f..4000f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Text("Região lida", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Spacer(Modifier.height(6.dp))
                SegmentedSelector(CaptureRegion.entries, cp.region, { if (it == CaptureRegion.FULL) "Tela inteira" else "Metade inferior" }, { r -> vm.updateCapture { it.copy(region = r) } })
                Spacer(Modifier.height(6.dp))
                SwitchRow("Realçar contraste antes do OCR", cp.enhanceContrast) { v -> vm.updateCapture { it.copy(enhanceContrast = v) } }
                Text("Resolução máxima: ${cp.maxWidth} px de largura", style = MaterialTheme.typography.labelMedium, color = c.textSecondary)
                Slider(
                    value = cp.maxWidth.toFloat(),
                    onValueChange = { v -> vm.updateCapture { it.copy(maxWidth = (v / 60).roundToInt() * 60) } },
                    valueRange = 540f..1440f,
                    colors = SliderDefaults.colors(thumbColor = c.brand, activeTrackColor = c.brand),
                )
                Text("Alterações de captura valem a partir do próximo início do assistente.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
            }
        }
        item {
            Group("Diagnóstico local") {
                InfoRow("Status", assistant.status.label)
                InfoRow("Frames analisados", assistant.framesAnalyzed.toString())
                InfoRow("Tempo médio de OCR", assistant.avgOcrMs?.let { "${it.roundToInt()} ms" } ?: Br.DASH)
                InfoRow("Falhas de leitura", assistant.ocrFailures.toString())
                NavRow("Laboratório de OCR", "Teste a leitura com capturas de tela ou texto", onOpenOcrLab)
            }
        }
        item {
            Group("Aparelho") {
                SegmentedSelector(ThemeMode.entries, s.theme, { it.label }, vm::setTheme)
                Spacer(Modifier.height(8.dp))
                NavRow("Permissões", "Sobreposição, notificações, bateria", onOpenPermissions)
                NavRow("Privacidade e dados", "O que é armazenado e por quê", onOpenPrivacy)
            }
        }
        item {
            Text(
                "Driver Intelligence ${BuildConfig.VERSION_NAME} · processamento 100% local",
                style = MaterialTheme.typography.bodySmall,
                color = c.textTertiary,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
        }
    }
}

private val TEXT_SCALES = listOf(1f, 1.15f, 1.3f)

private fun scaleLabel(v: Float) = when {
    v < 1.07f -> "Normal"
    v < 1.22f -> "Grande"
    else -> "Extra grande"
}

private fun modeLabel(m: OverlayMode) = when (m) {
    OverlayMode.MINIMIZED -> "Mínimo"
    OverlayMode.COMPACT -> "Compacto"
    OverlayMode.EXPANDED -> "Expandido"
}

@Composable
fun Group(title: String, subtitle: String? = null, content: @Composable () -> Unit) {
    val c = DiTheme.colors
    DiCard {
        Text(title.uppercase(), style = MaterialTheme.typography.labelSmall, color = c.textTertiary)
        if (subtitle != null) {
            Spacer(Modifier.height(2.dp))
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
        }
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
fun NavRow(title: String, subtitle: String?, onClick: () -> Unit) {
    val c = DiTheme.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = c.textPrimary)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = c.textTertiary)
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = DiTheme.colors
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = c.brand))
    }
}
