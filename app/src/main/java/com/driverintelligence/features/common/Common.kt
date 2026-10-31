package com.driverintelligence.features.common

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.driverintelligence.designsystem.DiNumbers
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.DiTopBar
import com.driverintelligence.designsystem.Tag
import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.recognition.NumberNormalizer
import com.driverintelligence.domain.util.Br
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Converte o texto digitado (vírgula ou ponto) em número. */
fun parseInput(s: String): Double? = NumberNormalizer.parse(s)

/** Formata um número para preencher um campo (até 2 casas, vírgula decimal, sem zeros sobrando). */
fun formatInput(d: Double?): String {
    if (d == null || !d.isFinite()) return ""
    val s = String.format(Br.locale, "%.2f", d).trimEnd('0').trimEnd(',')
    return s
}

private val timeFmt = DateTimeFormatter.ofPattern("HH:mm", Br.locale)
private val dayFmt = DateTimeFormatter.ofPattern("dd/MM", Br.locale)
private val fullFmt = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm", Br.locale)
private val headerFmt = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", Br.locale)

fun timeLabel(ms: Long): String = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(timeFmt)
fun shortDateTime(ms: Long): String {
    val dt = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())
    return if (dt.toLocalDate() == LocalDate.now()) "Hoje, ${dt.format(timeFmt)}" else "${dt.format(dayFmt)} ${dt.format(timeFmt)}"
}
fun fullDateTime(ms: Long): String = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(fullFmt)
fun parseFullDateTime(s: String): Long? = try {
    java.time.LocalDateTime.parse(s.trim(), fullFmt).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
} catch (_: Exception) {
    null
}
fun todayHeader(): String = LocalDate.now().format(headerFmt).replaceFirstChar { it.uppercase() }

/** Tela rolável padrão com barra superior. */
@Composable
fun ScreenList(
    title: String,
    onBack: (() -> Unit)? = null,
    subtitle: String? = null,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
    /** Aplica o recuo da barra de navegação do sistema (telas sem a barra de abas). */
    insetBottom: Boolean = onBack != null,
    content: LazyListScope.() -> Unit,
) {
    val c = DiTheme.colors
    Column(Modifier.fillMaxSize().background(c.background)) {
        DiTopBar(title = title, onBack = onBack, subtitle = subtitle, actions = actions)
        LazyColumn(
            modifier = Modifier.fillMaxSize().imePadding().then(if (insetBottom) Modifier.navigationBarsPadding() else Modifier),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
    }
}

@Composable
fun OfferRow(offer: AnalyzedOffer, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val c = DiTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(c.surface)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(4.dp).height(36.dp).clip(RoundedCornerShape(2.dp)).background(c.of(offer.classification)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(Br.money(offer.fare), style = DiNumbers.medium, color = c.textPrimary)
                Spacer(Modifier.width(8.dp))
                if (offer.isRegistered) Tag("REALIZADA", c.positive)
                if (offer.source == DataSource.MANUAL) {
                    Spacer(Modifier.width(4.dp))
                    Tag("MANUAL", c.textSecondary)
                }
            }
            Text(
                listOfNotNull(offer.category, Br.km(offer.totalKm), Br.minutes(offer.totalMin)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = c.textSecondary,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(Br.perKm(offer.revenuePerKm), style = DiNumbers.small, color = c.of(offer.classification))
            Text(shortDateTime(offer.detectedAt), style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        }
    }
}

@Composable
fun TripRow(trip: Trip, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val c = DiTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(c.surface)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).clip(RoundedCornerShape(4.dp)).background(c.of(trip.classification)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(Br.money(trip.fare), style = DiNumbers.medium, color = c.textPrimary)
            Text(
                listOfNotNull(trip.category, trip.destination?.take(28), Br.km(trip.totalKm)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = c.textSecondary,
                maxLines = 1,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            val profit = trip.estimatedProfit
            Text(
                if (profit == null) "lucro —" else "lucro ${Br.money(profit)}",
                style = DiNumbers.small,
                color = when {
                    profit == null -> c.textTertiary
                    profit > 0 -> c.positive
                    else -> c.negative
                },
            )
            Text(shortDateTime(trip.startedAt), style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        }
    }
}

fun classificationLabel(c: Classification?): String = c?.label ?: "Sem classificação"
