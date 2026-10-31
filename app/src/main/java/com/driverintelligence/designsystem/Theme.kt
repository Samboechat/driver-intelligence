package com.driverintelligence.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.ThemeMode

/**
 * Paleta própria. O verde/amarelo/vermelho/cinza são reservados para semântica de
 * rentabilidade — a cor da marca (azul-lavanda) nunca é usada para indicar resultado.
 */
@Immutable
data class DiColors(
    val isDark: Boolean,
    val background: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val surfaceSunken: Color,
    val outline: Color,
    val outlineStrong: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val brand: Color,
    val brandSoft: Color,
    val onBrand: Color,
    val positive: Color,
    val positiveSoft: Color,
    val warning: Color,
    val warningSoft: Color,
    val negative: Color,
    val negativeSoft: Color,
    val neutral: Color,
    val neutralSoft: Color,
) {
    fun of(c: Classification?): Color = when (c) {
        Classification.GREEN -> positive
        Classification.YELLOW -> warning
        Classification.RED -> negative
        Classification.GRAY, null -> neutral
    }

    fun softOf(c: Classification?): Color = when (c) {
        Classification.GREEN -> positiveSoft
        Classification.YELLOW -> warningSoft
        Classification.RED -> negativeSoft
        Classification.GRAY, null -> neutralSoft
    }
}

val DarkDiColors = DiColors(
    isDark = true,
    background = Color(0xFF0A0C0F),
    surface = Color(0xFF12161B),
    surfaceRaised = Color(0xFF181D24),
    surfaceSunken = Color(0xFF0D1014),
    outline = Color(0xFF222831),
    outlineStrong = Color(0xFF323B47),
    textPrimary = Color(0xFFF1F4F8),
    textSecondary = Color(0xFFA0AAB8),
    textTertiary = Color(0xFF6B7584),
    brand = Color(0xFF8FA2FF),
    brandSoft = Color(0x298FA2FF),
    onBrand = Color(0xFF0A0C0F),
    positive = Color(0xFF2FD180),
    positiveSoft = Color(0x262FD180),
    warning = Color(0xFFF2C14E),
    warningSoft = Color(0x26F2C14E),
    negative = Color(0xFFFF5D5D),
    negativeSoft = Color(0x26FF5D5D),
    neutral = Color(0xFF8A94A6),
    neutralSoft = Color(0x268A94A6),
)

val LightDiColors = DiColors(
    isDark = false,
    background = Color(0xFFF5F6F8),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFFFFFFF),
    surfaceSunken = Color(0xFFECEEF2),
    outline = Color(0xFFE1E4E9),
    outlineStrong = Color(0xFFC9CED6),
    textPrimary = Color(0xFF0E1116),
    textSecondary = Color(0xFF545E6C),
    textTertiary = Color(0xFF8790A0),
    brand = Color(0xFF4457E0),
    brandSoft = Color(0x1F4457E0),
    onBrand = Color(0xFFFFFFFF),
    positive = Color(0xFF0E9F59),
    positiveSoft = Color(0x1F0E9F59),
    warning = Color(0xFFB07A00),
    warningSoft = Color(0x24B07A00),
    negative = Color(0xFFD63A3A),
    negativeSoft = Color(0x1FD63A3A),
    neutral = Color(0xFF6B7484),
    neutralSoft = Color(0x1F6B7484),
)

val LocalDiColors = staticCompositionLocalOf { DarkDiColors }

/** Estilos numéricos com algarismos tabulares — valores alinhados e sem "pulos" ao atualizar. */
object DiNumbers {
    private const val TNUM = "tnum"
    val hero = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 40.sp, lineHeight = 44.sp, letterSpacing = (-1.2).sp, fontFeatureSettings = TNUM)
    val large = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 26.sp, lineHeight = 30.sp, letterSpacing = (-0.6).sp, fontFeatureSettings = TNUM)
    val medium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, lineHeight = 22.sp, letterSpacing = (-0.2).sp, fontFeatureSettings = TNUM)
    val small = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 18.sp, fontFeatureSettings = TNUM)
}

private val DiTypography = Typography(
    headlineLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 28.sp, lineHeight = 34.sp, letterSpacing = (-0.6).sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.4).sp),
    headlineSmall = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 26.sp, letterSpacing = (-0.2).sp),
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 18.sp, lineHeight = 24.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp),
    titleSmall = TextStyle(fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 0.2.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 11.sp, lineHeight = 14.sp, letterSpacing = 0.8.sp),
)

@Composable
fun DriverIntelligenceTheme(mode: ThemeMode = ThemeMode.DARK, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
    }
    val di = if (dark) DarkDiColors else LightDiColors
    val scheme = if (dark) {
        darkColorScheme(
            primary = di.brand, onPrimary = di.onBrand, primaryContainer = di.brandSoft, onPrimaryContainer = di.textPrimary,
            secondary = di.brand, onSecondary = di.onBrand,
            background = di.background, onBackground = di.textPrimary,
            surface = di.surface, onSurface = di.textPrimary, surfaceVariant = di.surfaceRaised, onSurfaceVariant = di.textSecondary,
            surfaceContainer = di.surface, surfaceContainerHigh = di.surfaceRaised, surfaceContainerHighest = di.surfaceRaised,
            surfaceContainerLow = di.surface, surfaceContainerLowest = di.surfaceSunken,
            outline = di.outlineStrong, outlineVariant = di.outline, error = di.negative, onError = di.onBrand,
        )
    } else {
        lightColorScheme(
            primary = di.brand, onPrimary = di.onBrand, primaryContainer = di.brandSoft, onPrimaryContainer = di.textPrimary,
            secondary = di.brand, onSecondary = di.onBrand,
            background = di.background, onBackground = di.textPrimary,
            surface = di.surface, onSurface = di.textPrimary, surfaceVariant = di.surfaceSunken, onSurfaceVariant = di.textSecondary,
            surfaceContainer = di.surface, surfaceContainerHigh = di.surfaceRaised, surfaceContainerHighest = di.surfaceSunken,
            surfaceContainerLow = di.surface, surfaceContainerLowest = di.surface,
            outline = di.outlineStrong, outlineVariant = di.outline, error = di.negative, onError = di.onBrand,
        )
    }
    CompositionLocalProvider(LocalDiColors provides di) {
        MaterialTheme(colorScheme = scheme, typography = DiTypography, content = content)
    }
}

object DiTheme {
    val colors: DiColors
        @Composable get() = LocalDiColors.current
}
