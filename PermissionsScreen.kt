package com.driverintelligence.features.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.prefs.SettingsRepository
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiNumbers
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.designsystem.Tag
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.permissions.PermissionSnapshot
import com.driverintelligence.permissions.Permissions
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class OnboardingViewModel @Inject constructor(private val settings: SettingsRepository) : ViewModel() {
    fun finish(onDone: () -> Unit) = viewModelScope.launch {
        settings.setOnboardingDone(true)
        onDone()
    }
}

/**
 * Fluxo de permissões com explicação individual antes de cada pedido.
 * Nada é solicitado em bloco; cada etapa diz por que é necessária.
 */
@Composable
fun PermissionsScreen(
    onboarding: Boolean,
    onBack: (() -> Unit)?,
    onConfigureVehicle: () -> Unit,
    onFinish: () -> Unit,
    vm: OnboardingViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val c = DiTheme.colors
    var snap by remember { mutableStateOf(Permissions.snapshot(context)) }
    LifecycleResumeEffect(Unit) {
        snap = Permissions.snapshot(context)
        onPauseOrDispose { }
    }
    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        snap = Permissions.snapshot(context)
    }

    ScreenList(
        title = if (onboarding) "Bem-vindo" else "Permissões",
        subtitle = if (onboarding) "Configure o assistente em poucos passos" else null,
        onBack = onBack,
        insetBottom = true,
    ) {
        if (onboarding) {
            item {
                DiCard(raised = true) {
                    Text("Seu copiloto financeiro", style = MaterialTheme.typography.headlineSmall, color = c.textPrimary)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "O Driver Intelligence lê as ofertas que aparecem no Uber Driver e mostra, numa janela flutuante, quanto a corrida rende por km, por hora e de lucro estimado — em cerca de dois segundos. A decisão de aceitar é sempre sua: o app nunca toca na tela.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.textSecondary,
                    )
                }
            }
        }
        item {
            Step(
                n = 1,
                title = "Sobrepor a outros apps",
                why = "Necessária para exibir a janela de análise por cima do Uber Driver. A janela é pequena, móvel e não bloqueia os botões do app.",
                granted = snap.overlay,
                required = true,
                action = "Autorizar",
            ) { context.startActivity(Permissions.overlaySettingsIntent(context)) }
        }
        item {
            Step(
                n = 2,
                title = "Notificações",
                why = "O Android exige uma notificação enquanto a captura está ativa. Por ela você pausa ou encerra o assistente a qualquer momento.",
                granted = snap.notifications,
                required = false,
                action = "Permitir",
            ) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    context.startActivity(Permissions.appNotificationSettingsIntent(context))
                }
            }
        }
        item {
            Step(
                n = 3,
                title = "Captura de tela",
                why = "Pedida pelo próprio Android toda vez que você inicia o assistente. Escolha compartilhar a tela inteira. O texto é lido no aparelho e nenhuma imagem é salva ou enviada.",
                granted = null,
                required = true,
                action = null,
                onAction = null,
            )
        }
        item {
            Step(
                n = 4,
                title = "Serviço em primeiro plano",
                why = "Mantém a leitura funcionando enquanto você usa o Uber Driver. Fica visível na barra de notificações e o processamento diminui automaticamente quando não há ofertas ou a tela está apagada.",
                granted = null,
                required = true,
                action = null,
                onAction = null,
            )
        }
        item {
            Step(
                n = 5,
                title = "Bateria (opcional)",
                why = "Alguns fabricantes encerram apps em segundo plano agressivamente. Se o assistente parar sozinho, remova a otimização de bateria para o Driver Intelligence.",
                granted = snap.batteryUnrestricted,
                required = false,
                action = "Abrir ajustes",
            ) { context.startActivity(Permissions.batterySettingsIntent()) }
        }
        item {
            Column {
                if (onboarding) {
                    SecondaryButton("Cadastrar meu veículo", onConfigureVehicle, Modifier.fillMaxWidth())
                    Spacer(Modifier.height(10.dp))
                }
                PrimaryButton(
                    if (onboarding) "Começar a usar" else "Concluído",
                    { if (onboarding) vm.finish(onFinish) else onFinish() },
                    Modifier.fillMaxWidth(),
                )
                if (onboarding && !snap.overlay) {
                    Spacer(Modifier.height(6.dp))
                    Text("Sem a sobreposição, você ainda pode usar a análise manual e o histórico.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                }
            }
        }
    }
}

@Composable
private fun Step(
    n: Int,
    title: String,
    why: String,
    granted: Boolean?,
    required: Boolean,
    action: String?,
    onAction: (() -> Unit)?,
) {
    val c = DiTheme.colors
    val status: Pair<String, Color> = when (granted) {
        true -> "CONCEDIDA" to c.positive
        false -> (if (required) "PENDENTE" else "OPCIONAL") to (if (required) c.warning else c.textTertiary)
        null -> "NO INÍCIO" to c.brand
    }
    DiCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(28.dp).clip(CircleShape).background(c.brandSoft), contentAlignment = Alignment.Center) {
                Text("$n", style = DiNumbers.small, color = c.brand)
            }
            Spacer(Modifier.width(10.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
            Tag(status.first, status.second)
        }
        Spacer(Modifier.height(8.dp))
        Text(why, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
        if (action != null && onAction != null && granted != true) {
            Spacer(Modifier.height(10.dp))
            SecondaryButton(action, onAction, Modifier.fillMaxWidth())
        }
    }
}
