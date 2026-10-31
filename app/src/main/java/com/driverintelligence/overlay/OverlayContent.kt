package com.driverintelligence.overlay

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.driverintelligence.R
import com.driverintelligence.designsystem.DiColors
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.domain.detection.OutcomeSource
import com.driverintelligence.domain.detection.TripPhase
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.Metric
import com.driverintelligence.domain.overlay.OverlayAction
import com.driverintelligence.domain.overlay.OverlayMode
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.util.Br
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.roundToInt

private val CardShape = RoundedCornerShape(22.dp)
private val TileShape = RoundedCornerShape(14.dp)
private const val TNUM = "tnum"

private fun num(size: TextUnit, weight: FontWeight = FontWeight.SemiBold, color: Color = Color.Unspecified, spacing: TextUnit = 0.sp) =
    TextStyle(fontSize = size, fontWeight = weight, color = color, letterSpacing = spacing, fontFeatureSettings = TNUM)

private fun label(color: Color, size: TextUnit = 9.sp) =
    TextStyle(fontSize = size, fontWeight = FontWeight.SemiBold, letterSpacing = 0.9.sp, color = color)

/**
 * Janela flutuante: cartão de leitura rápida ao volante.
 * Hierarquia: veredito (cor) → valor → R$/km e R$/h (com meta) → lucro, distância, tempo → justificativa.
 */
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
    val base = LocalDensity.current
    // A escala aumenta texto E tamanho do cartão juntos, mantendo as proporções.
    CompositionLocalProvider(LocalDensity provides Density(base.density * state.textScale, base.fontScale)) {
        OverlayBody(state, onDrag, onDragEnd, onAction, onOpacityStep, callbacks)
    }
}

@Composable
private fun OverlayBody(
    state: OverlayUiState,
    onDrag: (Float, Float) -> Unit,
    onDragEnd: () -> Unit,
    onAction: (OverlayAction) -> Unit,
    onOpacityStep: (Float) -> Unit,
    callbacks: OverlayCallbacks,
) {
    val c = DiTheme.colors
    val analysis = state.analysis.takeIf { state.kind == OverlayKind.OFFER }
    val trip = state.trip.takeIf { state.kind == OverlayKind.TRIP }
    val summary = state.summary.takeIf { state.kind == OverlayKind.SUMMARY }
    val accent = when (state.kind) {
        OverlayKind.OFFER -> c.of(analysis?.decision?.classification)
        OverlayKind.TRIP -> phaseColor(trip?.phase, c)
        OverlayKind.SUMMARY -> if (summary?.cancelled == true) c.neutral else c.positive
        OverlayKind.BLOCKED, OverlayKind.ERROR, OverlayKind.CAPTURE_STOPPED -> c.warning
        OverlayKind.PAUSED -> c.neutral
        else -> c.brand
    }

    // Brilho na borda quando uma oferta nova é reconhecida.
    val flash = remember { Animatable(0f) }
    LaunchedEffect(state.pulse) {
        if (state.pulse > 0) {
            flash.snapTo(1f)
            flash.animateTo(0f, tween(1100))
        }
    }

    val drag = Modifier.pointerInput(Unit) {
        detectDragGestures(onDragEnd = onDragEnd, onDragCancel = onDragEnd) { change, amount ->
            change.consume()
            onDrag(amount.x, amount.y)
        }
    }

    if (state.mode == OverlayMode.MINIMIZED) {
        Bubble(analysis, state.trip, accent, flash.value, state.opacity, drag, pulsing = state.kind == OverlayKind.READING) {
            onAction(OverlayAction.TOGGLE)
        }
        return
    }

    val expanded = state.mode == OverlayMode.EXPANDED
    Column(
        Modifier
            .padding(8.dp)
            .width(if (expanded) 304.dp else 264.dp)
            .graphicsLayer { alpha = state.opacity }
            .shadow(18.dp, CardShape, ambientColor = Color.Black, spotColor = Color.Black)
            .clip(CardShape)
            .background(c.surface)
            .background(Brush.verticalGradient(listOf(accent.copy(alpha = 0.20f), Color.Transparent), endY = 420f))
            .border(1.dp + 2.dp * flash.value, lerpColor(c.outlineStrong, accent, flash.value), CardShape)
            .animateContentSize(tween(220)),
    ) {
        Box(Modifier.fillMaxWidth().height(3.dp).background(Brush.horizontalGradient(listOf(accent, accent.copy(alpha = 0.15f)))))
        Header(state, analysis, trip, accent, drag, onAction)
        Column(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 12.dp)) {
            when (state.kind) {
                OverlayKind.OFFER -> analysis?.let { OfferBody(it, accent, expanded, state.offerAccepted, callbacks) }
                OverlayKind.TRIP -> trip?.let { TripBody(it, accent, expanded, callbacks) }
                OverlayKind.SUMMARY -> summary?.let { SummaryBody(it, callbacks) }
                OverlayKind.READING -> StatusBody(accent, "Lendo a oferta…", "Mantenha o cartão da oferta visível.", pulsing = true)
                OverlayKind.WAITING -> StatusBody(accent, "Aguardando oferta", "A análise aparece aqui em cerca de 2 segundos.")
                OverlayKind.PAUSED -> StatusBody(accent, "Análise pausada", "Nenhuma tela está sendo lida agora.")
                OverlayKind.CAPTURE_STOPPED -> StatusBody(accent, "Captura interrompida", state.message ?: "Autorize de novo para continuar.")
                OverlayKind.BLOCKED -> StatusBody(accent, "Leitura indisponível", state.message ?: "Esta tela bloqueia captura. Use a inserção manual.")
                OverlayKind.ERROR -> StatusBody(accent, "Falha na leitura", state.message ?: "Tentando novamente…")
            }
            val showActions = (expanded && state.kind != OverlayKind.SUMMARY && state.kind != OverlayKind.TRIP) || state.kind == OverlayKind.CAPTURE_STOPPED || state.kind == OverlayKind.BLOCKED || state.kind == OverlayKind.PAUSED
            if (showActions) {
                Spacer(Modifier.height(12.dp))
                Actions(state, accent, expanded, callbacks, onOpacityStep)
            }
        }
        state.today?.let { TodayFooter(it, c) }
    }
}

// ───────────────────────── Cabeçalho ─────────────────────────

@Composable
private fun Header(state: OverlayUiState, analysis: OfferAnalysis?, trip: LiveTrip?, accent: Color, drag: Modifier, onAction: (OverlayAction) -> Unit) {
    val c = DiTheme.colors
    Row(
        Modifier.fillMaxWidth().then(drag).padding(start = 14.dp, end = 4.dp, top = 8.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (trip != null) {
            Pill(trip.phase.label.uppercase(), accent)
            trip.timeline.offer.offer.category?.let {
                Spacer(Modifier.width(8.dp))
                Text(it.uppercase(), style = label(c.textTertiary), maxLines = 1)
            }
        } else if (analysis != null) {
            Verdict(analysis.decision.classification, accent)
            analysis.offer.category?.let {
                Spacer(Modifier.width(8.dp))
                Text(it.uppercase(), style = label(c.textTertiary), maxLines = 1)
            }
        } else {
            Box(Modifier.size(18.dp).clip(RoundedCornerShape(5.dp)).background(c.brandSoft), contentAlignment = Alignment.Center) {
                Text("DI", style = TextStyle(fontSize = 8.sp, fontWeight = FontWeight.Black, color = c.brand))
            }
            Spacer(Modifier.width(8.dp))
            Text("ASSISTENTE", style = label(c.textTertiary))
        }
        Spacer(Modifier.weight(1f))
        HeaderIcon(
            if (state.mode == OverlayMode.EXPANDED) R.drawable.ic_collapse else R.drawable.ic_expand,
            if (state.mode == OverlayMode.EXPANDED) "Recolher" else "Expandir",
        ) { onAction(if (state.mode == OverlayMode.EXPANDED) OverlayAction.COLLAPSE else OverlayAction.EXPAND) }
        HeaderIcon(R.drawable.ic_minimize, "Minimizar") { onAction(OverlayAction.MINIMIZE) }
    }
}

@Composable
private fun Verdict(classification: Classification, accent: Color) = Pill(classification.shortLabel, accent)

@Composable
private fun Pill(text: String, accent: Color) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(accent.copy(alpha = 0.18f)).padding(horizontal = 9.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(accent))
        Spacer(Modifier.width(6.dp))
        Text(text, style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp, color = accent), maxLines = 1)
    }
}

@Composable
private fun HeaderIcon(icon: Int, description: String, onClick: () -> Unit) {
    val c = DiTheme.colors
    Box(
        Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = c.textSecondary, modifier = Modifier.size(18.dp))
    }
}

// ───────────────────────── Oferta ─────────────────────────

@Composable
private fun OfferBody(a: OfferAnalysis, accent: Color, expanded: Boolean, accepted: Boolean, callbacks: OverlayCallbacks) {
    val c = DiTheme.colors
    val f = a.financial
    val d = a.decision
    val gray = d.classification == Classification.GRAY

    // Valor + nota
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("VALOR DA CORRIDA", style = label(c.textTertiary))
            Text(Br.money(f.grossRevenue), style = num(31.sp, color = c.textPrimary, spacing = (-0.8).sp), maxLines = 1)
            a.offer.surgeAmount?.let {
                Text("inclui ${Br.money(it)} de dinâmico/bônus", style = TextStyle(fontSize = 10.sp, color = c.textTertiary))
            }
        }
        ScoreRing(d.score, accent, 50.dp)
    }

    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        BigMetric("R$ POR KM", f.revenuePerKm, a.goalOf(Metric.REVENUE_PER_KM), a.met(Metric.REVENUE_PER_KM), Modifier.weight(1f))
        BigMetric(
            if (a.usedRealistic) "R$/H REAL EST." else "R$ POR HORA",
            a.basis.revenuePerHour,
            a.goalOf(Metric.REVENUE_PER_HOUR),
            a.met(Metric.REVENUE_PER_HOUR),
            Modifier.weight(1f),
            decimals = 0,
        )
    }

    Spacer(Modifier.height(10.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        MiniStat(
            "LUCRO EST.",
            Br.money(f.operatingProfit),
            f.operatingProfit?.let { if (it > 0) c.positive else c.negative } ?: c.textTertiary,
        )
        MiniStat("DISTÂNCIA", Br.km(f.totalDistanceKm), c.textPrimary, Alignment.CenterHorizontally)
        MiniStat(if (a.usedRealistic) "TEMPO REAL EST." else "TEMPO", Br.minutes(a.basis.totalTimeMin), c.textPrimary, Alignment.End)
    }

    Spacer(Modifier.height(10.dp))
    Text(
        d.headline,
        style = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, color = if (gray) c.textSecondary else accent),
        maxLines = if (expanded) 3 else 2,
        overflow = TextOverflow.Ellipsis,
    )

    if (a.usedRealistic && f.totalTimeMin != null) {
        val tf = a.timeFactors
        Spacer(Modifier.height(6.dp))
        Text(
            "App diz ${Br.minutes(f.totalTimeMin)} · na prática ~${Br.minutes(a.basis.totalTimeMin)}" +
                (tf?.let { if (it.isLearned) " (seu histórico)" else " (estimativa)" } ?: ""),
            style = TextStyle(fontSize = 10.sp, color = c.textSecondary, fontFeatureSettings = TNUM),
        )
    }
    a.percentile?.takeIf { !gray }?.let { p ->
        Spacer(Modifier.height(2.dp))
        Text(
            "R$/km melhor que ${(p * 100).roundToInt()}% das suas últimas ${a.benchmarkSize} ofertas",
            style = TextStyle(fontSize = 10.sp, color = if (p >= 0.5) c.positive else c.textSecondary, fontFeatureSettings = TNUM),
        )
    }

    a.fareTarget?.takeIf { !gray }?.let { t ->
        val gap = t.gap ?: 0.0
        Spacer(Modifier.height(6.dp))
        Text(
            if (gap >= 0) "${Br.money(gap)} acima do mínimo das suas metas"
            else "Valor justo: ${Br.money(t.minimumFare)} · faltam ${Br.money(-gap)}",
            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, color = if (gap >= 0) c.positive else c.warning, fontFeatureSettings = TNUM),
        )
    }

    if (!expanded) {
        if (d.isPartial && !gray) {
            Spacer(Modifier.height(4.dp))
            Text("Estimativa parcial · toque em expandir", style = TextStyle(fontSize = 9.sp, color = c.textTertiary))
        }
        Spacer(Modifier.height(10.dp))
        DecisionButtons(accepted, accent, callbacks)
        return
    }

    // ── Detalhes (modo expandido) ──
    Spacer(Modifier.height(12.dp))
    RouteBar(a, accent)

    Spacer(Modifier.height(12.dp))
    Section("CONTA DA CORRIDA") {
        Line("Faturamento bruto", Br.money(f.grossRevenue))
        Line(
            if (f.fuelIncludedInOperational) "Combustível (já no custo)" else "Combustível",
            f.fuelCost?.let { if (f.fuelIncludedInOperational) Br.money(it) else "− ${Br.money(it)}" } ?: Br.DASH,
            c.textSecondary,
        )
        Line("Custos operacionais", f.operationalCost?.let { "− ${Br.money(it)}" } ?: Br.DASH, c.textSecondary)
        Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).height(1.dp).background(c.outline))
        Line("Lucro estimado", Br.money(f.operatingProfit), f.operatingProfit?.let { if (it > 0) c.positive else c.negative }, bold = true)
        Line("Lucro/km · Lucro/h", "${Br.decimal(f.profitPerKm)} · ${Br.decimal(f.profitPerHour, 0)}")
        Line("Margem", Br.percent(f.operatingMargin))
    }

    a.fareTarget?.let { t ->
        Spacer(Modifier.height(10.dp))
        Section("VALOR MÍNIMO PARA SUAS METAS") {
            Line("Mínimo (${t.bindingGoal})", Br.money(t.minimumFare), bold = true)
            t.breakEven?.let { Line("Ponto de equilíbrio (lucro zero)", Br.money(it), c.textSecondary) }
        }
    }

    f.emptyReturn?.let { er ->
        Spacer(Modifier.height(10.dp))
        Section("RETORNO VAZIO (CENÁRIO)") {
            Line(Br.km(er.distanceKm), er.cost?.let { "− ${Br.money(it)}" } ?: Br.DASH, c.textSecondary)
            er.profitAfterReturn?.let { Line("Lucro com retorno", Br.money(it), if (it > 0) c.positive else c.negative) }
        }
    }

    val reasons = d.reasons.filterNot { it.startsWith("Estimativa parcial") }.take(3)
    if (reasons.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        reasons.forEach { r ->
            Row(Modifier.padding(vertical = 1.dp), verticalAlignment = Alignment.Top) {
                Text("•", style = TextStyle(fontSize = 11.sp, color = accent))
                Spacer(Modifier.width(6.dp))
                Text(r, style = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, color = c.textSecondary))
            }
        }
    }

    Spacer(Modifier.height(8.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            if (a.source == DataSource.OCR) "Leitura ${(a.confidence * 100).roundToInt()}%" else "Entrada manual",
            style = TextStyle(fontSize = 10.sp, color = c.textTertiary, fontFeatureSettings = TNUM),
        )
        if (d.isPartial) {
            Text("  ·  estimativa parcial", style = TextStyle(fontSize = 10.sp, color = c.warning))
        }
    }
}

@Composable
private fun ScoreRing(score: Double?, color: Color, size: Dp) {
    val c = DiTheme.colors
    val target = (score ?: 0.0).toFloat().coerceIn(0f, 1f)
    val animated by animateFloatAsState(target, tween(700), label = "score")
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val s = 5.dp.toPx()
            val arc = Size(this.size.width - s, this.size.height - s)
            val tl = Offset(s / 2, s / 2)
            drawArc(c.outline, 135f, 270f, false, tl, arc, style = Stroke(s, cap = StrokeCap.Round))
            if (score != null && animated > 0f) {
                drawArc(color, 135f, 270f * animated, false, tl, arc, style = Stroke(s, cap = StrokeCap.Round))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(score?.let { "${(it * 100).roundToInt()}" } ?: "—", style = num(15.sp, FontWeight.Bold, c.textPrimary))
            Text("nota", style = TextStyle(fontSize = 7.sp, color = c.textTertiary))
        }
    }
}

@Composable
private fun BigMetric(title: String, value: Double?, goal: Double?, met: Boolean?, modifier: Modifier, decimals: Int = 2) {
    val c = DiTheme.colors
    val status = when (met) {
        true -> c.positive
        false -> c.negative
        null -> c.textTertiary
    }
    Row(modifier.clip(TileShape).background(c.surfaceSunken)) {
        Box(Modifier.width(3.dp).height(62.dp).background(status))
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(title, style = label(c.textTertiary))
            Spacer(Modifier.height(2.dp))
            Text(
                value?.let { Br.decimal(it, decimals) } ?: "—",
                style = num(22.sp, FontWeight.Bold, if (value != null) c.textPrimary else c.textTertiary, (-0.4).sp),
                maxLines = 1,
            )
            Text(
                goal?.let { "meta ${Br.decimal(it, decimals)}" } ?: if (value == null) "sem dado" else "medido",
                style = TextStyle(fontSize = 9.sp, color = status, fontWeight = FontWeight.Medium, fontFeatureSettings = TNUM),
            )
        }
    }
}

@Composable
private fun MiniStat(title: String, value: String, color: Color, align: Alignment.Horizontal = Alignment.Start) {
    val c = DiTheme.colors
    Column(horizontalAlignment = align) {
        Text(title, style = label(c.textTertiary, 8.sp))
        Text(value, style = num(14.sp, FontWeight.SemiBold, color), maxLines = 1)
    }
}

/** Barra proporcional: quanto da distância é busca (não paga) e quanto é viagem. */
@Composable
private fun RouteBar(a: OfferAnalysis, accent: Color) {
    val c = DiTheme.colors
    val pickup = (a.offer.pickupDistanceKm ?: 0.0).coerceAtLeast(0.0)
    val trip = (a.offer.tripDistanceKm ?: 0.0).coerceAtLeast(0.0)
    val total = (pickup + trip).takeIf { it > 0 } ?: return
    val pickupShare = (pickup / total).toFloat().coerceIn(0.04f, 0.96f)
    Text("PERCURSO", style = label(c.textTertiary))
    Spacer(Modifier.height(5.dp))
    Row(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp))) {
        Box(Modifier.weight(pickupShare).fillMaxHeight().background(c.neutral.copy(alpha = 0.55f)))
        Box(Modifier.width(2.dp).fillMaxHeight().background(c.surface))
        Box(Modifier.weight(1f - pickupShare).fillMaxHeight().background(accent))
    }
    Spacer(Modifier.height(4.dp))
    Row(Modifier.fillMaxWidth()) {
        Text(
            "Busca ${Br.km(a.offer.pickupDistanceKm)} · ${Br.minutes(a.offer.pickupTimeMin)}",
            style = TextStyle(fontSize = 10.sp, color = c.textSecondary, fontFeatureSettings = TNUM),
            modifier = Modifier.weight(1f),
        )
        Text(
            "Viagem ${Br.km(a.offer.tripDistanceKm)} · ${Br.minutes(a.offer.tripTimeMin)}",
            style = TextStyle(fontSize = 10.sp, color = c.textPrimary, fontFeatureSettings = TNUM),
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    val c = DiTheme.colors
    Column(Modifier.fillMaxWidth().clip(TileShape).background(c.surfaceSunken).padding(horizontal = 10.dp, vertical = 8.dp)) {
        Text(title, style = label(c.textTertiary))
        Spacer(Modifier.height(4.dp))
        content()
    }
}

@Composable
private fun Line(title: String, value: String, valueColor: Color? = null, bold: Boolean = false) {
    val c = DiTheme.colors
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = TextStyle(fontSize = 11.sp, color = c.textSecondary, fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal), modifier = Modifier.weight(1f))
        Text(value, style = num(if (bold) 13.sp else 12.sp, if (bold) FontWeight.Bold else FontWeight.Medium, valueColor ?: c.textPrimary), maxLines = 1)
    }
}

// ───────────────────────── Estados sem oferta ─────────────────────────

@Composable
private fun StatusBody(color: Color, title: String, message: String, pulsing: Boolean = false) {
    val c = DiTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        PulseDot(color, pulsing)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.textPrimary))
            Text(message, style = TextStyle(fontSize = 11.sp, lineHeight = 15.sp, color = c.textSecondary))
        }
    }
}

@Composable
private fun PulseDot(color: Color, pulsing: Boolean) {
    val t = rememberInfiniteTransition(label = "pulse")
    val scale by t.animateFloat(1f, if (pulsing) 1.8f else 1f, infiniteRepeatable(tween(900), RepeatMode.Restart), label = "s")
    val alpha by t.animateFloat(0.5f, if (pulsing) 0f else 0.5f, infiniteRepeatable(tween(900), RepeatMode.Restart), label = "a")
    Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(10.dp).graphicsLayer { scaleX = scale; scaleY = scale; this.alpha = alpha }.clip(CircleShape).background(color))
        Box(Modifier.size(10.dp).clip(CircleShape).background(color))
    }
}

// ───────────────────────── Rodapé do dia ─────────────────────────

@Composable
private fun TodayFooter(t: TodayStrip, c: DiColors) {
    Column(Modifier.fillMaxWidth().background(c.surfaceSunken.copy(alpha = 0.8f)).padding(horizontal = 14.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("HOJE", style = label(c.textTertiary))
            Spacer(Modifier.width(8.dp))
            Text(Br.money(t.revenue), style = num(12.sp, FontWeight.Bold, c.textPrimary))
            Text(
                "  ·  ${t.trips} ${if (t.trips == 1) "corrida" else "corridas"}",
                style = TextStyle(fontSize = 10.sp, color = c.textSecondary),
                modifier = Modifier.weight(1f),
            )
            val goal = t.goal
            if (goal != null && goal > 0) {
                Text(Br.percent(t.revenue / goal), style = num(11.sp, FontWeight.SemiBold, if (t.revenue >= goal) c.positive else c.brand))
            } else {
                t.profit?.let { Text("lucro ${Br.money(it)}", style = num(10.sp, FontWeight.Medium, c.positive)) }
            }
        }
        val goal = t.goal
        if (goal != null && goal > 0) {
            Spacer(Modifier.height(5.dp))
            val p = (t.revenue / goal).toFloat().coerceIn(0f, 1f)
            Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(c.outline)) {
                Box(Modifier.fillMaxWidth(p).height(4.dp).clip(RoundedCornerShape(2.dp)).background(if (p >= 1f) c.positive else c.brand))
            }
        }
    }
}

// ───────────────────────── Ações ─────────────────────────

@Composable
private fun Actions(state: OverlayUiState, accent: Color, expanded: Boolean, callbacks: OverlayCallbacks, onOpacityStep: (Float) -> Unit) {
    val c = DiTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        when (state.kind) {
            OverlayKind.CAPTURE_STOPPED -> FilledAction("Retomar captura", c.brand, Modifier.fillMaxWidth()) { callbacks.onRestartCapture() }
            OverlayKind.PAUSED -> FilledAction("Retomar análise", c.brand, Modifier.fillMaxWidth()) { callbacks.onPauseToggle() }
            OverlayKind.OFFER -> if (state.analysis?.offer?.fare != null) DecisionButtons(state.offerAccepted, accent, callbacks)
            else -> Unit
        }
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            GhostAction("Manual", c.textPrimary, Modifier.weight(1f)) { callbacks.onManualInput() }
            if (state.kind != OverlayKind.CAPTURE_STOPPED && state.kind != OverlayKind.PAUSED) {
                GhostAction("Pausar", c.textPrimary, Modifier.weight(1f)) { callbacks.onPauseToggle() }
            }
            GhostAction("Fechar", c.negative, Modifier.weight(1f)) { callbacks.onClose() }
        }
        if (expanded) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Transparência", style = TextStyle(fontSize = 11.sp, color = c.textSecondary), modifier = Modifier.weight(1f))
                GhostAction("−", c.textPrimary, Modifier.width(40.dp)) { onOpacityStep(-0.1f) }
                Text(
                    "${(state.opacity * 100).roundToInt()}%",
                    style = num(11.sp, FontWeight.Medium, c.textSecondary),
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
                GhostAction("+", c.textPrimary, Modifier.width(40.dp)) { onOpacityStep(0.1f) }
            }
        }
    }
}

@Composable
private fun FilledAction(text: String, color: Color, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.height(40.dp).clip(RoundedCornerShape(12.dp)).background(color).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color(0xFF0A0C0F)), maxLines = 1)
    }
}

@Composable
private fun GhostAction(text: String, color: Color, modifier: Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = DiTheme.colors
    Box(
        modifier
            .height(36.dp)
            .clip(RoundedCornerShape(11.dp))
            .background(c.surfaceRaised)
            .border(1.dp, c.outline, RoundedCornerShape(11.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = color), maxLines = 1)
    }
}

// ───────────────────────── Minimizado ─────────────────────────

@Composable
private fun Bubble(
    analysis: OfferAnalysis?,
    trip: LiveTrip?,
    accent: Color,
    flash: Float,
    opacity: Float,
    drag: Modifier,
    pulsing: Boolean,
    onClick: () -> Unit,
) {
    val c = DiTheme.colors
    val score = analysis?.decision?.score?.toFloat()?.coerceIn(0f, 1f)
    val animated by animateFloatAsState(score ?: 0f, tween(700), label = "bubble")
    Box(
        Modifier
            .padding(8.dp)
            .size(64.dp)
            .graphicsLayer { alpha = opacity }
            .shadow(14.dp, CircleShape)
            .clip(CircleShape)
            .background(c.surface)
            .then(drag)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Driver Intelligence minimizado. Toque para abrir." },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(64.dp)) {
            val s = 4.dp.toPx() + 3.dp.toPx() * flash
            val arc = Size(size.width - s, size.height - s)
            val tl = Offset(s / 2, s / 2)
            drawArc(c.outline, -90f, 360f, false, tl, arc, style = Stroke(s))
            if (score != null) drawArc(accent, -90f, 360f * animated, false, tl, arc, style = Stroke(s, cap = StrokeCap.Round))
            else drawArc(accent.copy(alpha = 0.7f), -90f, 360f, false, tl, arc, style = Stroke(s))
        }
        if (trip != null && analysis == null) {
            val now = rememberNow()
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${(now - trip.timeline.acceptedAt) / 60_000}", style = num(17.sp, FontWeight.Bold, accent))
                Text("min", style = TextStyle(fontSize = 8.sp, color = c.textTertiary))
            }
        } else if (analysis != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(analysis.financial.revenuePerKm?.let { Br.decimal(it) } ?: "—", style = num(15.sp, FontWeight.Bold, accent))
                Text("R$/km", style = TextStyle(fontSize = 8.sp, color = c.textTertiary))
            }
        } else {
            PulseDot(accent, pulsing)
        }
    }
}

// ───────────────────────── Utilidades ─────────────────────────

private fun OfferAnalysis.met(metric: Metric): Boolean? =
    decision.metricScores.firstOrNull { it.metric == metric }?.meetsTarget

private fun OfferAnalysis.goalOf(metric: Metric): Double? =
    decision.metricScores.firstOrNull { it.metric == metric }?.target

private fun lerpColor(a: Color, b: Color, t: Float): Color {
    val f = t.coerceIn(0f, 1f)
    return Color(
        red = a.red + (b.red - a.red) * f,
        green = a.green + (b.green - a.green) * f,
        blue = a.blue + (b.blue - a.blue) * f,
        alpha = a.alpha + (b.alpha - a.alpha) * f,
    )
}

// ───────────────────────── Aceitei / Recusei ─────────────────────────

@Composable
private fun DecisionButtons(accepted: Boolean, accent: Color, callbacks: OverlayCallbacks) {
    val c = DiTheme.colors
    if (accepted) {
        GhostAction("✓ Aceita · acompanhando a corrida", c.positive, Modifier.fillMaxWidth(), enabled = false) {}
        return
    }
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        GhostAction("✕ Recusei", c.textSecondary, Modifier.weight(1f)) { callbacks.onReject() }
        FilledAction("✓ Aceitei", accent, Modifier.weight(1.4f)) { callbacks.onAccept() }
    }
}

// ───────────────────────── Corrida ao vivo ─────────────────────────

private fun phaseColor(phase: TripPhase?, c: DiColors): Color = when (phase) {
    TripPhase.TO_PICKUP -> c.brand
    TripPhase.WAITING -> c.warning
    TripPhase.ON_TRIP -> c.positive
    else -> c.neutral
}

/** Relógio que redesenha a cada segundo enquanto o cartão está visível. */
@Composable
private fun rememberNow(): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000)
        }
    }
    return now
}

private fun clock(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val sec = total % 60
    return if (h > 0) String.format(Br.locale, "%d:%02d:%02d", h, m, sec) else String.format(Br.locale, "%02d:%02d", m, sec)
}

@Composable
private fun TripBody(t: LiveTrip, accent: Color, expanded: Boolean, callbacks: OverlayCallbacks) {
    val c = DiTheme.colors
    val now = rememberNow()
    val tl = t.timeline
    val elapsedMs = now - tl.acceptedAt
    val elapsedMin = elapsedMs / 60_000.0
    val predicted = if (t.predictedPickupMin != null && t.predictedTripMin != null) t.predictedPickupMin + t.predictedTripMin else null
    val ratio = predicted?.takeIf { it > 0 }?.let { elapsedMin / it }
    val progressColor = when {
        ratio == null -> accent
        ratio > 1.3 -> c.negative
        ratio > 1.0 -> c.warning
        else -> accent
    }

    Row(verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f)) {
            Text("TEMPO DESDE O ACEITE", style = label(c.textTertiary))
            Text(clock(elapsedMs), style = num(32.sp, FontWeight.Bold, c.textPrimary, (-0.8).sp))
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("PREVISTO", style = label(c.textTertiary))
            Text(predicted?.let { "~${Br.minutes(it)}" } ?: Br.DASH, style = num(15.sp, FontWeight.SemiBold, c.textSecondary))
        }
    }
    Spacer(Modifier.height(8.dp))
    val p = ratio?.toFloat()?.coerceIn(0f, 1f) ?: 0f
    Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(c.outline)) {
        Box(Modifier.fillMaxWidth(p).height(8.dp).clip(RoundedCornerShape(4.dp)).background(progressColor))
    }
    if (ratio != null && ratio > 1.0) {
        Spacer(Modifier.height(4.dp))
        Text(
            "Corrida ${((ratio - 1) * 100).roundToInt()}% mais longa que o previsto",
            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, color = progressColor),
        )
    }

    // Ganho por hora ao vivo: cai conforme o tempo passa.
    Spacer(Modifier.height(10.dp))
    val fare = t.fare
    val liveHour = if (fare != null && elapsedMin >= 1.0) fare / (elapsedMin / 60.0) else null
    val projectedHour = if (fare != null && predicted != null && predicted > 0) fare / (predicted / 60.0) else null
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        BigMetric("R$/H ATÉ AGORA", liveHour, t.goalPerHour, liveHour?.let { it >= t.goalPerHour }, Modifier.weight(1f), decimals = 0)
        BigMetric("R$/H PREVISTO", projectedHour, t.goalPerHour, projectedHour?.let { it >= t.goalPerHour }, Modifier.weight(1f), decimals = 0)
    }

    Spacer(Modifier.height(10.dp))
    val pickupEnd = tl.arrivedAt ?: tl.startedAt
    StageLine("Busca", ((pickupEnd ?: now) - tl.acceptedAt) / 60_000.0, t.offeredPickupMin, done = pickupEnd != null, active = t.phase == TripPhase.TO_PICKUP)
    val arrived = tl.arrivedAt
    if (arrived != null && tl.startedAt == null) {
        StageLine("Espera", (now - arrived) / 60_000.0, null, done = false, active = true)
    }
    tl.startedAt?.let { st -> StageLine("Viagem", (now - st) / 60_000.0, t.offeredTripMin, done = false, active = true) }

    if (expanded) {
        val cost = t.estimatedCost
        Spacer(Modifier.height(10.dp))
        Section("CORRIDA") {
            Line("Valor", Br.money(fare))
            Line("Custo estimado", cost?.let { "− ${Br.money(it)}" } ?: Br.DASH, c.textSecondary)
            Line("Lucro estimado", Br.money(if (fare != null && cost != null) fare - cost else null), c.positive, bold = true)
            Line("Aceite", if (tl.acceptSource == OutcomeSource.MANUAL) "informado por você" else "detectado na tela", c.textSecondary)
        }
    }

    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        GhostAction("Cancelada", c.negative, Modifier.weight(1f)) { callbacks.onCancelTrip() }
        FilledAction("Finalizar corrida", accent, Modifier.weight(1.4f)) { callbacks.onFinishTrip() }
    }
}

@Composable
private fun StageLine(title: String, minutes: Double, offered: Double?, done: Boolean, active: Boolean) {
    val c = DiTheme.colors
    val over = offered != null && minutes > offered * 1.15
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(8.dp).clip(CircleShape).background(
                when {
                    done -> c.positive
                    active -> c.brand
                    else -> c.outline
                },
            ),
        )
        Spacer(Modifier.width(8.dp))
        Text(title, style = TextStyle(fontSize = 12.sp, color = c.textSecondary), modifier = Modifier.weight(1f))
        Text(
            Br.minutes(minutes) + (offered?.let { "  (app: ${Br.minutes(it)})" } ?: ""),
            style = num(12.sp, FontWeight.Medium, if (over) c.warning else c.textPrimary),
        )
    }
}

@Composable
private fun SummaryBody(s: TripSummary, callbacks: OverlayCallbacks) {
    val c = DiTheme.colors
    val tl = s.timeline
    if (s.cancelled) {
        StatusBody(c.neutral, "Corrida cancelada", "Nada foi registrado e o tempo não entra no aprendizado.")
    } else {
        Text("CORRIDA CONCLUÍDA", style = label(c.textTertiary))
        Text(Br.money(tl.offer.offer.fare), style = num(28.sp, FontWeight.Bold, c.textPrimary))
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BigMetric("R$/H REAL", s.revenuePerHour, null, null, Modifier.weight(1f), decimals = 0)
            Column(Modifier.weight(1f).clip(TileShape).background(c.surfaceSunken).padding(horizontal = 10.dp, vertical = 8.dp)) {
                Text("LUCRO EST.", style = label(c.textTertiary))
                Spacer(Modifier.height(2.dp))
                val profit = s.profit
                Text(Br.money(profit), style = num(18.sp, FontWeight.Bold, profit?.let { if (it > 0) c.positive else c.negative } ?: c.textTertiary))
            }
        }
        Spacer(Modifier.height(10.dp))
        Section("TEMPO") {
            Line("Real", Br.minutes(tl.totalMin), bold = true)
            Line("O app prometeu", Br.minutes(s.offeredTotalMin), c.textSecondary)
            s.predictedTotalMin?.let { Line("Previsão do Driver Intelligence", Br.minutes(it), c.textSecondary) }
            Line("Busca · viagem", "${Br.minutes(tl.actualPickupMin)} · ${Br.minutes(tl.actualTripMin)}", c.textSecondary)
        }
        Spacer(Modifier.height(6.dp))
        Text(
            if (s.registered) "Registrada no histórico com os tempos reais. As próximas previsões ficam mais precisas."
            else "Tempos guardados para melhorar as próximas previsões.",
            style = TextStyle(fontSize = 10.sp, lineHeight = 13.sp, color = c.textSecondary),
        )
    }
    Spacer(Modifier.height(10.dp))
    GhostAction("OK", c.textPrimary, Modifier.fillMaxWidth()) { callbacks.onDismissSummary() }
}
