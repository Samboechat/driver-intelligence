package com.driverintelligence.features.common

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.driverintelligence.designsystem.ClassificationBadge
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiNumbers
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.LinearMeter
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.recognition.OfferAnalysis
import com.driverintelligence.domain.util.Br
import kotlin.math.roundToInt

/** Resultado completo de uma análise: classificação, justificativa, indicadores e custos. */
@Composable
fun AnalysisCard(a: OfferAnalysis, modifier: Modifier = Modifier, showScores: Boolean = true) {
    val c = DiTheme.colors
    val f = a.financial
    val d = a.decision
    val color = c.of(d.classification)

    DiCard(modifier, borderColor = color.copy(alpha = 0.45f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(Br.money(f.grossRevenue), style = DiNumbers.large, color = c.textPrimary, modifier = Modifier.weight(1f))
            ClassificationBadge(d.classification)
        }
        Spacer(Modifier.height(8.dp))
        Text(d.headline, style = MaterialTheme.typography.bodyMedium, color = if (d.classification == Classification.GRAY) c.textSecondary else color)
        d.score?.let { s ->
            Spacer(Modifier.height(10.dp))
            LinearMeter(s.toFloat(), color = color)
            Spacer(Modifier.height(4.dp))
            Text("Pontuação ${(s * 100).roundToInt()} de 100", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Stat("R$/km", Br.money(f.revenuePerKm), Modifier.weight(1f))
            Stat("R$/hora", Br.money(f.revenuePerHour), Modifier.weight(1f))
            Stat("Lucro est.", Br.money(f.operatingProfit), Modifier.weight(1f), valueColor = f.operatingProfit?.let { if (it > 0) c.positive else c.negative })
        }
        Spacer(Modifier.height(8.dp))
        InfoRow("Faturamento bruto", Br.money(f.grossRevenue))
        InfoRow(
            "Combustível",
            Br.money(f.fuelCost),
            note = if (f.fuelIncludedInOperational) "já incluído no custo operacional — não descontado de novo" else null,
        )
        InfoRow("Receita após combustível", Br.money(f.revenueAfterFuel))
        InfoRow("Custos operacionais", Br.money(f.operationalCost))
        InfoRow("Lucro operacional estimado", Br.money(f.operatingProfit), emphasize = true, valueColor = f.operatingProfit?.let { if (it > 0) c.positive else c.negative })
        InfoRow("Lucro por km · por hora", "${Br.perKm(f.profitPerKm)} · ${Br.perHour(f.profitPerHour)}")
        InfoRow("Margem operacional", Br.percent(f.operatingMargin))
        InfoRow("Distância total", Br.km(f.totalDistanceKm), note = "busca ${Br.km(f.unproductiveDistanceKm)} (improdutiva)")
        InfoRow("Tempo total", Br.minutes(f.totalTimeMin), note = "busca ${Br.minutes(f.unproductiveTimeMin)}")
        InfoRow("Eficiência da corrida", Br.percent(f.productiveDistanceShare), note = "parte da distância que é remunerada")
        f.emptyReturn?.let { er ->
            InfoRow(
                "Retorno vazio (cenário)",
                er.cost?.let { "−${Br.money(it)}" } ?: Br.km(er.distanceKm),
                note = buildString {
                    append(er.description)
                    er.profitAfterReturn?.let { append(" · lucro com retorno ${Br.money(it)}") }
                },
            )
        }
        if (f.isCostEstimatePartial) {
            Spacer(Modifier.height(6.dp))
            Text(
                "Estimativa parcial — custos não configurados: ${f.missingCosts.joinToString(", ") { it.label.lowercase() }}.",
                style = MaterialTheme.typography.bodySmall,
                color = c.warning,
            )
        }
        Text("Lucro líquido não é calculado por corrida: depende de custos fixos e impostos.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)

        if (showScores && d.metricScores.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Text("COMO A CLASSIFICAÇÃO FOI FEITA", style = MaterialTheme.typography.labelSmall, color = c.textTertiary)
            Spacer(Modifier.height(6.dp))
            d.metricScores.forEach { m ->
                Row(Modifier.fillMaxWidth().height(26.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(if (m.meetsTarget) c.positive else c.negative))
                    Spacer(Modifier.width(8.dp))
                    Text(m.metric.label, style = MaterialTheme.typography.bodySmall, color = c.textSecondary, modifier = Modifier.weight(1f))
                    Text("${(m.score * 100).roundToInt()}", style = DiNumbers.small, color = c.textPrimary)
                    Text("  peso ${(m.weight * 100).roundToInt()}", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
                }
            }
        }
        if (d.reasons.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            d.reasons.take(6).forEach { r ->
                Text("• $r", style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier, valueColor: androidx.compose.ui.graphics.Color? = null) {
    val c = DiTheme.colors
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(c.surfaceSunken).padding(10.dp)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = c.textTertiary)
        Spacer(Modifier.height(2.dp))
        Text(value, style = DiNumbers.small, color = valueColor ?: c.textPrimary, maxLines = 1)
    }
}
