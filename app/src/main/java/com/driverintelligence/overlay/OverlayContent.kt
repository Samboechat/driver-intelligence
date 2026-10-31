package com.driverintelligence.overlay

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.driverintelligence.R
import com.driverintelligence.designsystem.DiNumbers
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.overlay.OverlayAction
import com.driverintelligence.domain.overlay.OverlayMode
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.util.Br
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.roundToInt

private val OverlayShape = RoundedCornerShape(18.dp)

/** Experiência visual própria do overlay: compacta, legível ao volante, sem cobrir os botões do app. */
@Composable
fun OverlayContent(
    stateFlow: StateFlow<OverlayUiState>,
    onDrag: (Float, Float) -> Unit,
    onDragEnd: () -> Unit,
    onAction: (OverlayAction) -> Unit,
    onOpacityStep: (Float) -> Unit,
    callbacks: OverlayCallbacks,
) {
    val state by stateFlow.collectAsState()
    val c = DiTheme.colors
    val accent = when (state.kind) {
        OverlayKind.OFFER -> c.of(state.analysis?.decision?.classification)
        OverlayKind.BLOCKED, OverlayKind.ERROR, OverlayKind.CAPTURE_STOPPED -> c.warning
        else -> c.brand
    }

    // Feedback visual quando uma oferta nova é reconhecida.
    val flash = remember { Animatable(0f) }
    LaunchedEffect(state.pulse) {
        if (state.pulse > 0) {
            flash.snapTo(1f)
            flash.animateTo(0f, tween(900))
        }
    }

    val dragModifier = Modifier.pointerInput(Unit) {
        detectDragGestures(onDragEnd = onDragEnd, onDragCancel = onDragEnd) { change, amount ->
            change.consume()
            onDrag(amount.x, amount.y)
        }
    }

    if (state.mode == OverlayMode.MINIMIZED) {
        Box(
            Modifier
                .padding(4.dp)
                .size(52.dp)
                .graphicsLayer { alpha = state.opacity }
                .clip(CircleShape)
                .background(c.surfaceRaised)
                .border(2.dp + (3.dp * flash.value), accent.copy(alpha = 0.6f + 0.4f * flash.value), CircleShape)
                .then(dragModifier)
                .clickable { onAction(OverlayAction.TOGGLE) }
                .semantics { contentDescription = "Driver Intelligence minimizado. Toque para abrir." },
            contentAlignment = Alignment.Center,
        ) {
            val a = state.analysis
            if (state.kind == OverlayKind.OFFER && a != null) {
                Text(
                    a.financial.revenuePerKm?.let { Br.decimal(it) } ?: "—",
                    style = DiNumbers.small.copy(fontSize = 13.sp),
                    color = accent,
                )
            } else {
                StatusDot(accent, pulsing = state.kind == OverlayKind.READING)
            }
        }
        return
    }

    val width: Dp = if (state.mode == OverlayMode.EXPANDED) 284.dp else 236.dp
    Column(
        Modifier
            .padding(4.dp)
            .width(width)
            .graphicsLayer { alpha = state.opacity }
            .clip(OverlayShape)
            .background(c.surface.copy(alpha = 0.97f))
            .border(1.dp + (2.dp * flash.value), if (flash.value > 0f) accent.copy(alpha = flash.value) else c.outlineStrong, OverlayShape)
            .animateContentSize(),
    ) {
        Header(state, accent, dragModifier, onAction)
        Box(Modifier.fillMaxWidth().height(1.dp).background(c.outline))
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            when (state.kind) {
                OverlayKind.OFFER -> state.analysis?.let { OfferBody(it, expanded = state.mode == OverlayMode.EXPANDED) }
                OverlayKind.READING -> Hint("Lendo oferta…", "Mantenha a oferta visível na tela.")
                OverlayKind.WAITING -> Hint("Aguardando oferta", "A análise aparece aqui assim que uma oferta surgir.")
                OverlayKind.PAUSED -> Hint("Análise pausada", "Nenhuma tela está sendo lida agora.")
                OverlayKind.CAPTURE_STOPPED -> Hint("Captura interrompida", state.message ?: "Autorize novamente para continuar.")
                OverlayKind.BLOCKED -> Hint("Leitura indisponível", state.message ?: "O app exibido bloqueia a captura de tela.")
                OverlayKind.ERROR -> Hint("Falha na leitura", state.message ?: "Tentando novamente…")
            }
            if (state.mode == OverlayMode.EXPANDED || state.kind in setOf(OverlayKind.CAPTURE_STOPPED, OverlayKind.BLOCKED, OverlayKind.PAUSED)) {
                Spacer(Modifier.height(12.dp))
                Actions(state, callbacks, onOpacityStep)
            }
        }
    }
}

@Composable
private fun Header(state: OverlayUiState, accent: Color, dragModifier: Modifier, onAction: (OverlayAction) -> Unit) {
    val c = DiTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .then(dragModifier)
            .padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(c.brandSoft), contentAlignment = Alignment.Center) {
            Text("DI", style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.Bold, color = c.brand))
        }
        Spacer(Modifier.width(8.dp))
        val status = when (state.kind) {
            OverlayKind.OFFER -> state.analysis?.offer?.category ?: "Oferta"
            OverlayKind.READING -> "Lendo"
            OverlayKind.PAUSED -> "Pausado"
            else -> "Assistente"
        }
        Text(status.uppercase(), style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp, color = c.textTertiary), modifier = Modifier.weight(1f), maxLines = 1)
        StatusDot(accent, pulsing = state.kind == OverlayKind.READING, size = 7.dp)
        Spacer(Modifier.width(4.dp))
        HeaderIcon(
            if (state.mode == OverlayMode.EXPANDED) R.drawable.ic_collapse else R.drawable.ic_expand,
            if (state.mode == OverlayMode.EXPANDED) "Recolher" else "Expandir",
        ) { onAction(if (state.mode == OverlayMode.EXPANDED) OverlayAction.COLLAPSE else OverlayAction.EXPAND) }
        HeaderIcon(R.drawable.ic_minimize, "Minimizar") { onAction(OverlayAction.MINIMIZE) }
    }
}

@Composable
private fun HeaderIcon(icon: Int, description: String, onClick: () -> Unit) {
    val c = DiTheme.colors
    Box(
        Modifier.size(32.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = c.textSecondary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun StatusDot(color: Color, pulsing: Boolean, size: Dp = 12.dp) {
    val transition = rememberInfiniteTransition(label = "dot")
    val a by transition.animateFloat(
        initialValue = 1f,
        targetValue = if (pulsing) 0.25f else 1f,
        animationSpec = infiniteRepeatable(tween(650), RepeatMode.Reverse),
        label = "dotAlpha",
    )
    Box(Modifier.size(size).graphicsLayer { alpha = a }.clip(CircleShape).background(color))
}

@Composable
private fun Hint(title: String, message: String) {
    val c = DiTheme.colors
    Text(title, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.textPrimary))
    Spacer(Modifier.height(2.dp))
    Text(message, style = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, color = c.textSecondary))
}

@Composable
private fun OfferBody(a: OfferAnalysis, expanded: Boolean) {
    val c = DiTheme.colors
    val f = a.financial
    val d = a.decision
    val color = c.of(d.classification)

    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(Br.money(f.grossRevenue), style = DiNumbers.large, color = c.textPrimary, modifier = Modifier.weight(1f), maxLines = 1)
        Text(
            d.classification.shortLabel,
            style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp, color = color),
            modifier = Modifier.clip(RoundedCornerShape(50)).background(c.softOf(d.classification)).padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Metric("R$/KM", f.revenuePerKm?.let { Br.money(it) }, Modifier.weight(1f), highlight = d.classification != Classification.GRAY)
        Metric("R$/HORA", f.revenuePerHour?.let { Br.money(it) }, Modifier.weight(1f), highlight = d.classification != Classification.GRAY)
    }
    if (d.classification == Classification.GRAY || expanded) {
        Spacer(Modifier.height(10.dp))
        Text(d.headline, style = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, color = if (d.classification == Classification.GRAY) c.textSecondary else color))
    }
    if (!expanded) {
        if (d.isPartial && d.classification != Classification.GRAY) {
            Spacer(Modifier.height(6.dp))
            Text("Estimativa parcial", style = TextStyle(fontSize = 10.sp, color = c.textTertiary))
        }
        return
    }

    Spacer(Modifier.height(10.dp))
    Box(Modifier.fillMaxWidth().height(1.dp).background(c.outline))
    Spacer(Modifier.height(8.dp))
    Row2("Lucro estimado", Br.money(f.operatingProfit), valueColor = f.operatingProfit?.let { if (it > 0) c.positive else c.negative })
    Row2("Lucro/km · Lucro/h", "${Br.decimal(f.profitPerKm)} · ${Br.decimal(f.profitPerHour, 0)}")
    Row2("Custo estimado", Br.money(f.totalCost), note = if (f.fuelIncludedInOperational) "combustível incluído" else null)
    Row2("Distância total", Br.km(f.totalDistanceKm))
    Row2("Tempo total", Br.minutes(f.totalTimeMin))
    Row2("Busca (improdutiva)", "${Br.km(f.unproductiveDistanceKm)} · ${Br.minutes(f.unproductiveTimeMin)}")
    Row2("Eficiência", Br.percent(f.productiveDistanceShare))
    f.emptyReturn?.let { er ->
        Row2("Retorno vazio (cenário)", er.profitAfterReturn?.let { "lucro ${Br.money(it)}" } ?: Br.km(er.distanceKm), note = Br.km(er.distanceKm))
    }
    if (a.source == DataSource.OCR) {
        Row2("Confiança da leitura", "${(a.confidence * 100).roundToInt()}%")
    }
    if (d.isPartial) {
        Spacer(Modifier.height(4.dp))
        Text("Estimativa parcial: custos ou tempos ausentes.", style = TextStyle(fontSize = 10.sp, color = c.textTertiary))
    }
}

@Composable
private fun Metric(label: String, value: String?, modifier: Modifier, highlight: Boolean) {
    val c = DiTheme.colors
    Column(modifier.clip(RoundedCornerShape(10.dp)).background(c.surfaceSunken).padding(horizontal = 10.dp, vertical = 8.dp)) {
        Text(label, style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, color = c.textTertiary))
        Spacer(Modifier.height(2.dp))
        Text(value ?: "—", style = DiNumbers.medium.copy(fontSize = 16.sp), color = if (highlight && value != null) c.textPrimary else c.textTertiary, maxLines = 1, overflow = TextOverflow.Clip)
    }
}

@Composable
private fun Row2(label: String, value: String, valueColor: Color? = null, note: String? = null) {
    val c = DiTheme.colors
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = TextStyle(fontSize = 11.sp, color = c.textSecondary))
            if (note != null) Text(note, style = TextStyle(fontSize = 9.sp, color = c.textTertiary))
        }
        Text(value, style = DiNumbers.small.copy(fontSize = 12.sp), color = valueColor ?: c.textPrimary, maxLines = 1)
    }
}

@Composable
private fun Actions(state: OverlayUiState, callbacks: OverlayCallbacks, onOpacityStep: (Float) -> Unit) {
    val c = DiTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when (state.kind) {
            OverlayKind.CAPTURE_STOPPED -> ActionChip("Retomar captura", c.brand, Modifier.fillMaxWidth()) { callbacks.onRestartCapture() }
            OverlayKind.PAUSED -> ActionChip("Retomar análise", c.brand, Modifier.fillMaxWidth()) { callbacks.onPauseToggle() }
            OverlayKind.OFFER -> {
                val a = state.analysis
                if (a?.offer?.fare != null) {
                    ActionChip(
                        if (state.offerRegistered) "Corrida registrada ✓" else "Aceitei — registrar corrida",
                        if (state.offerRegistered) c.positive else c.textPrimary,
                        Modifier.fillMaxWidth(),
                        enabled = !state.offerRegistered,
                    ) { callbacks.onRegisterTrip() }
                }
            }
            else -> Unit
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            ActionChip("Manual", c.textPrimary, Modifier.weight(1f)) { callbacks.onManualInput() }
            if (state.kind != OverlayKind.CAPTURE_STOPPED && state.kind != OverlayKind.PAUSED) {
                ActionChip("Pausar", c.textPrimary, Modifier.weight(1f)) { callbacks.onPauseToggle() }
            }
            ActionChip("Fechar", c.negative, Modifier.weight(1f)) { callbacks.onClose() }
        }
        if (state.mode == OverlayMode.EXPANDED) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Transparência", style = TextStyle(fontSize = 11.sp, color = c.textSecondary), modifier = Modifier.weight(1f))
                ActionChip("−", c.textPrimary, Modifier.width(40.dp)) { onOpacityStep(-0.1f) }
                Text(
                    "${(state.opacity * 100).roundToInt()}%",
                    style = DiNumbers.small.copy(fontSize = 11.sp),
                    color = c.textSecondary,
                    modifier = Modifier.padding(horizontal = 6.dp),
                )
                ActionChip("+", c.textPrimary, Modifier.width(40.dp)) { onOpacityStep(0.1f) }
            }
        }
    }
}

@Composable
private fun ActionChip(text: String, color: Color, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = DiTheme.colors
    Box(
        modifier
            .height(34.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(c.surfaceRaised)
            .border(1.dp, c.outline, RoundedCornerShape(10.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = color), maxLines = 1)
    }
}
