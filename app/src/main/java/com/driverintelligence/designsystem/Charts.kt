package com.driverintelligence.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.driverintelligence.domain.util.Br
import kotlin.math.max

/**
 * Gráfico de barras desenhado em Canvas (sem biblioteca externa).
 * [secondary] desenha uma barra interna (ex.: lucro dentro do faturamento).
 */
@Composable
fun BarChart(
    values: List<Double>,
    labels: List<String>,
    modifier: Modifier = Modifier,
    secondary: List<Double?>? = null,
    color: Color = DiTheme.colors.brand,
    secondaryColor: Color = DiTheme.colors.positive,
    barColors: List<Color>? = null,
    valueFormatter: (Double) -> String = { Br.money(it) },
    height: Dp = 168.dp,
    labelEvery: Int = 1,
    description: String = "Gráfico de barras",
) {
    val c = DiTheme.colors
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = c.textTertiary, fontSize = 10.sp, letterSpacing = 0.sp)
    val valueStyle = TextStyle(color = c.textSecondary, fontSize = 10.sp, fontFeatureSettings = "tnum")
    val summary = remember(values, labels) {
        val maxIdx = values.indices.maxByOrNull { values[it] }
        if (maxIdx == null || values[maxIdx] <= 0.0) "$description: sem dados"
        else "$description. Maior valor: ${labels.getOrNull(maxIdx).orEmpty()} com ${valueFormatter(values[maxIdx])}."
    }
    Canvas(
        modifier
            .fillMaxWidth()
            .height(height)
            .semantics { contentDescription = summary },
    ) {
        val bottomPad = 18.dp.toPx()
        val topPad = 16.dp.toPx()
        val chartH = size.height - bottomPad - topPad
        val n = values.size
        if (n == 0) return@Canvas
        val maxV = max(values.maxOrNull() ?: 0.0, secondary?.filterNotNull()?.maxOrNull() ?: 0.0)

        // Linha de base e guias
        drawLine(c.outline, Offset(0f, topPad + chartH), Offset(size.width, topPad + chartH), 1.dp.toPx())
        drawLine(c.outline.copy(alpha = 0.5f), Offset(0f, topPad + chartH / 2), Offset(size.width, topPad + chartH / 2), 1.dp.toPx())

        if (maxV <= 0.0) {
            drawCenteredText(measurer, "Sem dados no período", valueStyle, Offset(size.width / 2, topPad + chartH / 2 - 14.dp.toPx()))
            return@Canvas
        }

        val slot = size.width / n
        val barW = (slot * 0.58f).coerceAtMost(28.dp.toPx())
        val radius = CornerRadius(4.dp.toPx(), 4.dp.toPx())
        val maxIdx = values.indices.maxByOrNull { values[it] } ?: 0

        values.forEachIndexed { i, v ->
            val x = slot * i + (slot - barW) / 2
            val h = (v / maxV * chartH).toFloat()
            val barColor = barColors?.getOrNull(i) ?: color
            if (h > 0f) {
                drawRoundRect(barColor.copy(alpha = if (i == maxIdx) 1f else 0.55f), Offset(x, topPad + chartH - h), Size(barW, h), radius)
            }
            val s = secondary?.getOrNull(i)
            if (s != null && s > 0.0) {
                val sh = (s / maxV * chartH).toFloat()
                val inner = barW * 0.42f
                drawRoundRect(secondaryColor, Offset(x + (barW - inner) / 2, topPad + chartH - sh), Size(inner, sh), radius)
            }
            if (i % labelEvery == 0 || i == n - 1) {
                labels.getOrNull(i)?.let {
                    drawCenteredText(measurer, it, labelStyle, Offset(x + barW / 2, topPad + chartH + 4.dp.toPx()))
                }
            }
        }
        // Valor máximo destacado
        val mx = slot * maxIdx + slot / 2
        val mh = (values[maxIdx] / maxV * chartH).toFloat()
        drawCenteredText(measurer, valueFormatter(values[maxIdx]), valueStyle, Offset(mx, topPad + chartH - mh - 14.dp.toPx()))
    }
}

/** Linha com área preenchida; pontos nulos interrompem a linha. */
@Composable
fun LineChart(
    values: List<Double?>,
    labels: List<String>,
    modifier: Modifier = Modifier,
    color: Color = DiTheme.colors.brand,
    valueFormatter: (Double) -> String = { Br.money(it) },
    height: Dp = 160.dp,
    labelEvery: Int = 1,
    description: String = "Gráfico de linha",
) {
    val c = DiTheme.colors
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = c.textTertiary, fontSize = 10.sp, letterSpacing = 0.sp)
    val valueStyle = TextStyle(color = c.textSecondary, fontSize = 10.sp, fontFeatureSettings = "tnum")
    val summary = remember(values) {
        val last = values.lastOrNull { it != null }
        if (last == null) "$description: sem dados" else "$description. Último valor: ${valueFormatter(last)}."
    }
    Canvas(modifier.fillMaxWidth().height(height).semantics { contentDescription = summary }) {
        val bottomPad = 18.dp.toPx()
        val topPad = 18.dp.toPx()
        val chartH = size.height - bottomPad - topPad
        val n = values.size
        if (n == 0) return@Canvas
        drawLine(c.outline, Offset(0f, topPad + chartH), Offset(size.width, topPad + chartH), 1.dp.toPx())
        val present = values.filterNotNull()
        if (present.isEmpty() || present.max() <= 0.0) {
            drawCenteredText(measurer, "Sem dados no período", valueStyle, Offset(size.width / 2, topPad + chartH / 2 - 14.dp.toPx()))
            return@Canvas
        }
        val maxV = present.max()
        val minV = minOf(0.0, present.min())
        val range = (maxV - minV).takeIf { it > 0 } ?: 1.0
        val step = if (n > 1) size.width / (n - 1) else size.width
        fun pt(i: Int, v: Double) = Offset(if (n > 1) step * i else size.width / 2, topPad + chartH - ((v - minV) / range * chartH).toFloat())

        val line = Path()
        val fill = Path()
        var started = false
        var firstX = 0f
        var lastPoint: Offset? = null
        values.forEachIndexed { i, v ->
            if (v == null) return@forEachIndexed
            val p = pt(i, v)
            if (!started) {
                line.moveTo(p.x, p.y)
                fill.moveTo(p.x, topPad + chartH)
                fill.lineTo(p.x, p.y)
                firstX = p.x
                started = true
            } else {
                line.lineTo(p.x, p.y)
                fill.lineTo(p.x, p.y)
            }
            lastPoint = p
        }
        lastPoint?.let { lp ->
            fill.lineTo(lp.x, topPad + chartH)
            fill.lineTo(firstX, topPad + chartH)
            fill.close()
            drawPath(fill, Brush.verticalGradient(listOf(color.copy(alpha = 0.28f), color.copy(alpha = 0f)), startY = topPad, endY = topPad + chartH))
            drawPath(line, color, style = Stroke(2.dp.toPx()))
            values.forEachIndexed { i, v -> if (v != null) drawCircle(color, 3.dp.toPx(), pt(i, v)) }
            drawCircle(c.background, 2.dp.toPx(), lp)
            val lastValue = values.last { it != null }!!
            drawCenteredText(measurer, valueFormatter(lastValue), valueStyle, Offset(lp.x.coerceIn(30.dp.toPx(), size.width - 30.dp.toPx()), lp.y - 16.dp.toPx()))
        }
        labels.forEachIndexed { i, label ->
            if (i % labelEvery == 0 || i == n - 1) {
                val x = if (n > 1) step * i else size.width / 2
                drawCenteredText(measurer, label, labelStyle, Offset(x.coerceIn(12.dp.toPx(), size.width - 12.dp.toPx()), topPad + chartH + 4.dp.toPx()))
            }
        }
    }
}

private fun DrawScope.drawCenteredText(measurer: TextMeasurer, text: String, style: TextStyle, topCenter: Offset) {
    val layout = measurer.measure(text, style)
    val x = (topCenter.x - layout.size.width / 2f).coerceIn(0f, (size.width - layout.size.width).coerceAtLeast(0f))
    drawText(layout, topLeft = Offset(x, topCenter.y))
}
