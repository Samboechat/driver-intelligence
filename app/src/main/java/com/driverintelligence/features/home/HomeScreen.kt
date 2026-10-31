package com.driverintelligence.features.home

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.R
import com.driverintelligence.capture.AssistantStatus
import com.driverintelligence.domain.detection.TripPhase
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.BarChart
import com.driverintelligence.designsystem.ClassificationBadge
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiNumbers
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.EmptyState
import com.driverintelligence.designsystem.MetricTile
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.ProgressRing
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.designsystem.SectionHeader
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.OfferRow
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.features.common.todayHeader

@Composable
fun HomeScreen(
    onOpenPermissions: () -> Unit,
    onManual: () -> Unit,
    onNewTrip: () -> Unit,
    onOpenOffers: () -> Unit,
    onAddVehicle: () -> Unit,
    onOpenGoals: () -> Unit,
    vm: HomeViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val c = DiTheme.colors

    LifecycleResumeEffect(Unit) {
        vm.refreshPermissions()
        onPauseOrDispose { }
    }

    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        // Com ou sem notificação, o assistente funciona; seguimos para a captura.
        vm.refreshPermissions()
        vm.startAssistant(context)
    }

    fun start() {
        val p = state.permissions
        when {
            p == null || !p.overlay -> onOpenPermissions()
            !p.notifications && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            else -> vm.startAssistant(context)
        }
    }

    ScreenList(title = "Driver Intelligence", subtitle = todayHeader()) {
        // Assistente
        item {
            AssistantCard(
                status = state.assistant.status,
                lastHeadline = state.assistant.tripPhase.takeIf { it != TripPhase.NONE && it != TripPhase.OFFER }
                    ?.let { "Corrida em andamento: ${it.label.lowercase()}. Acompanhe na janela flutuante." }
                    ?: state.assistant.lastAnalysis?.decision?.headline,
                message = state.assistant.message,
                onStart = ::start,
                onStop = { vm.stopAssistant(context) },
                onPause = { vm.pauseAssistant(context) },
                onResume = { vm.resumeAssistant(context) },
            )
        }
        val p = state.permissions
        if (p != null && !p.overlay) {
            item { Banner("Permita a sobreposição para ver a análise sobre o Uber Driver.", c.warning, action = "Configurar", onAction = onOpenPermissions) }
        }
        if (state.loaded && state.vehicle == null) {
            item { Banner("Cadastre seu veículo para calcular combustível e lucro.", c.brand, action = "Cadastrar", onAction = onAddVehicle) }
        }

        // Hoje
        item { Hero(state, onOpenGoals) }
        item {
            val t = state.today
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricTile(
                        "Lucro operacional",
                        Br.money(t.estimatedProfit),
                        Modifier.weight(1f),
                        caption = if (t.profitPartial || t.estimatedProfit == null) "estimativa parcial" else "estimado",
                        valueColor = t.estimatedProfit?.let { if (it >= 0) c.positive else c.negative },
                    )
                    MetricTile("Corridas", t.trips.toString(), Modifier.weight(1f), caption = Br.km(t.km).takeIf { t.km > 0 })
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricTile("Ganho médio/km", Br.perKm(t.revenuePerKm), Modifier.weight(1f))
                    MetricTile("Ganho médio/hora", Br.perHour(t.revenuePerOnlineHour ?: t.revenuePerRideHour), Modifier.weight(1f), caption = if (t.revenuePerOnlineHour != null) "por hora online" else "por hora em corrida")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MetricTile(
                        "Tempo trabalhado",
                        Br.minutes(t.onlineMinutes ?: t.rideMinutes.takeIf { it > 0 }),
                        Modifier.weight(1f),
                        caption = if (t.onlineMinutes != null) "online · ${Br.minutes(t.rideMinutes)} em corrida" else "em corrida",
                    )
                    MetricTile("Combustível", Br.money(t.fuelCost.takeIf { t.trips > 0 }), Modifier.weight(1f), estimated = true)
                }
            }
        }

        // Últimos 7 dias
        item {
            DiCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Últimos 7 dias", style = MaterialTheme.typography.titleMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
                    Legend(c.brand, "Faturamento")
                    Spacer(Modifier.width(10.dp))
                    Legend(c.positive, "Lucro")
                }
                Spacer(Modifier.height(12.dp))
                BarChart(
                    values = state.last7.map { it.revenue },
                    labels = state.last7.map { it.label },
                    secondary = state.last7.map { it.profit },
                    description = "Faturamento dos últimos 7 dias",
                )
            }
        }

        // Ofertas recentes
        item { SectionHeader("Ofertas analisadas", action = "Ver todas", onAction = onOpenOffers) }
        if (state.recentOffers.isEmpty()) {
            item {
                DiCard { EmptyState("Nenhuma oferta ainda", "Inicie o assistente e abra o Uber Driver, ou analise uma oferta manualmente.") }
            }
        } else {
            items(state.recentOffers, key = { it.id }) { OfferRow(it) }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton("Analisar oferta", onManual, Modifier.weight(1f), icon = painterResource(R.drawable.ic_scan))
                SecondaryButton("Registrar corrida", onNewTrip, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun AssistantCard(
    status: AssistantStatus,
    lastHeadline: String?,
    message: String?,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
) {
    val c = DiTheme.colors
    val active = status != AssistantStatus.STOPPED
    val dot = when (status) {
        AssistantStatus.RUNNING -> c.positive
        AssistantStatus.PAUSED -> c.warning
        AssistantStatus.CAPTURE_INTERRUPTED, AssistantStatus.BLOCKED -> c.negative
        AssistantStatus.STOPPED -> c.neutral
    }
    DiCard(raised = true, borderColor = if (active) dot.copy(alpha = 0.5f) else null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("Assistente de ofertas", style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
                Text(status.label, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
            }
        }
        val detail = message ?: lastHeadline ?: if (!active) {
            "Lê as ofertas na tela do Uber Driver e mostra a análise numa janela flutuante. Nada é aceito ou recusado automaticamente."
        } else null
        if (detail != null) {
            Spacer(Modifier.height(10.dp))
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
        }
        Spacer(Modifier.height(14.dp))
        if (!active) {
            PrimaryButton("Iniciar assistente", onStart, Modifier.fillMaxWidth(), icon = painterResource(R.drawable.ic_bolt))
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                when (status) {
                    AssistantStatus.PAUSED -> PrimaryButton("Retomar", onResume, Modifier.weight(1f), icon = painterResource(R.drawable.ic_play))
                    AssistantStatus.CAPTURE_INTERRUPTED -> PrimaryButton("Retomar captura", onStart, Modifier.weight(1f))
                    else -> SecondaryButton("Pausar", onPause, Modifier.weight(1f), icon = painterResource(R.drawable.ic_pause))
                }
                SecondaryButton("Encerrar", onStop, Modifier.weight(1f), color = c.negative)
            }
        }
    }
}

@Composable
private fun Hero(state: HomeUiState, onOpenGoals: () -> Unit) {
    val c = DiTheme.colors
    val goal = state.goals.dailyRevenue
    DiCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("FATURAMENTO DE HOJE", style = MaterialTheme.typography.labelSmall, color = c.textTertiary)
                Spacer(Modifier.height(6.dp))
                Text(Br.money(state.today.revenue), style = DiNumbers.hero, color = c.textPrimary)
                Spacer(Modifier.height(4.dp))
                if (goal != null) {
                    val remaining = (goal - state.today.revenue).coerceAtLeast(0.0)
                    Text(
                        if (remaining > 0) "Faltam ${Br.money(remaining)} para a meta de ${Br.money(goal)}" else "Meta diária atingida",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (remaining > 0) c.textSecondary else c.positive,
                    )
                } else {
                    Text("Sem meta diária definida", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                }
            }
            if (goal != null && goal > 0) {
                val progress = (state.today.revenue / goal).toFloat()
                ProgressRing(progress, color = if (progress >= 1f) c.positive else c.brand) {
                    Text(Br.percent(progress.toDouble().coerceAtMost(9.99)), style = DiNumbers.small, color = c.textPrimary)
                }
            } else {
                Box(Modifier.size(1.dp))
            }
        }
        if (goal == null) {
            Spacer(Modifier.height(8.dp))
            SecondaryButton("Configurar metas", onOpenGoals, Modifier.fillMaxWidth())
        }
        state.assistant.lastAnalysis?.let { a ->
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Última oferta: ${Br.money(a.financial.grossRevenue)}", style = MaterialTheme.typography.bodySmall, color = c.textSecondary, modifier = Modifier.weight(1f))
                ClassificationBadge(a.decision.classification)
            }
        }
    }
}

@Composable
private fun Legend(color: androidx.compose.ui.graphics.Color, label: String) {
    val c = DiTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(4.dp))
        Text(label, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
    }
}
