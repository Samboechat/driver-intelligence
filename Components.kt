package com.driverintelligence.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.driverintelligence.domain.model.Classification

val CardShape = RoundedCornerShape(20.dp)
val SmallShape = RoundedCornerShape(12.dp)

@Composable
fun DiCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    padding: PaddingValues = PaddingValues(16.dp),
    raised: Boolean = false,
    borderColor: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = DiTheme.colors
    Column(
        modifier = modifier
            .clip(CardShape)
            .background(if (raised) c.surfaceRaised else c.surface)
            .border(BorderStroke(1.dp, borderColor ?: c.outline), CardShape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(padding),
        content = content,
    )
}

/** Indicador com rótulo; [estimated] marca valores estimados pelo sistema (não medidos). */
@Composable
fun MetricTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    caption: String? = null,
    valueColor: Color? = null,
    estimated: Boolean = false,
) {
    val c = DiTheme.colors
    DiCard(modifier = modifier, padding = PaddingValues(horizontal = 14.dp, vertical = 12.dp)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = c.textTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, style = DiNumbers.medium, color = valueColor ?: c.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (estimated) {
                Text(" est.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
            }
        }
        if (caption != null) {
            Spacer(Modifier.height(2.dp))
            Text(caption, style = MaterialTheme.typography.bodySmall, color = c.textSecondary, maxLines = 2)
        }
    }
}

@Composable
fun ClassificationBadge(classification: Classification, modifier: Modifier = Modifier, short: Boolean = true) {
    val c = DiTheme.colors
    val color = c.of(classification)
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(c.softOf(classification))
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .semantics { contentDescription = "Classificação: ${classification.label}" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(6.dp))
        Text(
            if (short) classification.shortLabel else classification.label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
        )
    }
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    val c = DiTheme.colors
    Row(modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
        if (action != null && onAction != null) {
            Text(
                action,
                style = MaterialTheme.typography.labelLarge,
                color = c.brand,
                modifier = Modifier.clip(SmallShape).clickable(onClick = onAction).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
fun ProgressRing(
    progress: Float,
    modifier: Modifier = Modifier,
    size: Dp = 72.dp,
    stroke: Dp = 8.dp,
    color: Color = DiTheme.colors.positive,
    track: Color = DiTheme.colors.outline,
    content: @Composable () -> Unit = {},
) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), tween(700), label = "ring")
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val s = stroke.toPx()
            val arcSize = Size(this.size.width - s, this.size.height - s)
            val topLeft = Offset(s / 2, s / 2)
            drawArc(track, -90f, 360f, false, topLeft, arcSize, style = Stroke(s, cap = StrokeCap.Round))
            if (animated > 0f) {
                drawArc(color, -90f, 360f * animated, false, topLeft, arcSize, style = Stroke(s, cap = StrokeCap.Round))
            }
        }
        content()
    }
}

@Composable
fun LinearMeter(progress: Float, modifier: Modifier = Modifier, color: Color = DiTheme.colors.brand) {
    val c = DiTheme.colors
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), tween(600), label = "meter")
    Box(modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(c.outline)) {
        Box(Modifier.fillMaxWidth(animated).height(6.dp).clip(RoundedCornerShape(3.dp)).background(color))
    }
}

@Composable
fun EmptyState(title: String, message: String, modifier: Modifier = Modifier, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    val c = DiTheme.colors
    Column(modifier.fillMaxWidth().padding(vertical = 28.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(c.brandSoft), contentAlignment = Alignment.Center) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(c.brand))
        }
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
        Spacer(Modifier.height(4.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(14.dp))
            PrimaryButton(actionLabel, onAction)
        }
    }
}

@Composable
fun NumberField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    suffix: String? = null,
    supporting: String? = null,
    isError: Boolean = false,
    integer: Boolean = false,
) {
    DiTextField(
        label = label,
        value = value,
        onValueChange = { raw -> onValueChange(raw.filter { it.isDigit() || (!integer && (it == ',' || it == '.')) }) },
        modifier = modifier,
        suffix = suffix,
        supporting = supporting,
        isError = isError,
        keyboardType = if (integer) KeyboardType.Number else KeyboardType.Decimal,
    )
}

@Composable
fun DiTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    suffix: String? = null,
    supporting: String? = null,
    isError: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
) {
    val c = DiTheme.colors
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label) },
        suffix = if (suffix != null) {
            { Text(suffix, color = c.textTertiary) }
        } else null,
        supportingText = if (supporting != null) {
            { Text(supporting) }
        } else null,
        isError = isError,
        singleLine = singleLine,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = SmallShape,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = c.brand,
            unfocusedBorderColor = c.outline,
            focusedContainerColor = c.surfaceSunken,
            unfocusedContainerColor = c.surfaceSunken,
            focusedLabelColor = c.brand,
            unfocusedLabelColor = c.textSecondary,
            cursorColor = c.brand,
        ),
    )
}

@Composable
fun <T> SegmentedSelector(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val c = DiTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .clip(SmallShape)
            .background(c.surfaceSunken)
            .border(1.dp, c.outline, SmallShape)
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEach { opt ->
            val isSel = opt == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(9.dp))
                    .background(if (isSel) c.surfaceRaised else Color.Transparent)
                    .clickable { onSelect(opt) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label(opt),
                    style = MaterialTheme.typography.labelMedium,
                    color = if (isSel) c.textPrimary else c.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
fun InfoRow(label: String, value: String, modifier: Modifier = Modifier, valueColor: Color? = null, emphasize: Boolean = false, note: String? = null) {
    val c = DiTheme.colors
    Row(modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
            if (note != null) Text(note, style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
        }
        Text(
            value,
            style = if (emphasize) DiNumbers.medium else DiNumbers.small,
            color = valueColor ?: c.textPrimary,
            fontWeight = if (emphasize) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
fun DiTopBar(title: String, onBack: (() -> Unit)? = null, subtitle: String? = null, actions: @Composable RowScope.() -> Unit = {}) {
    val c = DiTheme.colors
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(start = if (onBack != null) 4.dp else 20.dp, end = 8.dp, top = 8.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Voltar", tint = c.textPrimary)
            }
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, color = c.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
        }
        actions()
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: Painter? = null, color: Color? = null) {
    val c = DiTheme.colors
    Button(
        onClick = onClick,
        modifier = modifier.height(50.dp),
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = color ?: c.brand,
            contentColor = c.onBrand,
            disabledContainerColor = c.outline,
            disabledContentColor = c.textTertiary,
        ),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: Painter? = null, color: Color? = null) {
    val c = DiTheme.colors
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.height(50.dp),
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(1.dp, c.outlineStrong),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = color ?: c.textPrimary),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun Tag(text: String, color: Color, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = modifier.clip(RoundedCornerShape(6.dp)).background(color.copy(alpha = 0.14f)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
fun Banner(text: String, color: Color, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    val c = DiTheme.colors
    Row(
        modifier.fillMaxWidth().clip(SmallShape).background(color.copy(alpha = 0.12f)).border(1.dp, color.copy(alpha = 0.35f), SmallShape).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(10.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = c.textPrimary, modifier = Modifier.weight(1f))
        if (action != null && onAction != null) {
            Spacer(Modifier.width(8.dp))
            Text(action, style = MaterialTheme.typography.labelLarge, color = color, modifier = Modifier.clip(SmallShape).clickable(onClick = onAction).padding(6.dp))
        }
    }
}
