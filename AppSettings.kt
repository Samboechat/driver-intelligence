package com.driverintelligence.domain.model

import com.driverintelligence.domain.overlay.OverlayMode

enum class ThemeMode(val label: String) { DARK("Escuro"), LIGHT("Claro"), SYSTEM("Seguir o sistema") }

enum class CaptureRegion(val label: String) {
    FULL("Tela inteira"),
    BOTTOM_HALF("Metade inferior (menos processamento)"),
}

data class OverlayPrefs(
    val mode: OverlayMode = OverlayMode.COMPACT,
    /** Opacidade do cartão (0,5..1). */
    val opacity: Float = 0.94f,
    val relX: Float = 0.03f,
    val relY: Float = 0.10f,
    val haptics: Boolean = true,
)

data class CapturePrefs(
    /** Intervalo entre análises quando há atividade de oferta. */
    val activeIntervalMs: Long = 600,
    /** Intervalo quando nada foi detectado recentemente (economia de bateria). */
    val idleIntervalMs: Long = 1200,
    val region: CaptureRegion = CaptureRegion.FULL,
    /** Pré-processamento de contraste antes do OCR. */
    val enhanceContrast: Boolean = false,
    /** Largura máxima do frame processado. */
    val maxWidth: Int = 1080,
)

data class AppSettings(
    val goals: Goals = Goals(),
    val scoring: ScoringConfig = ScoringConfig(),
    val emptyReturn: EmptyReturnScenario = EmptyReturnScenario.None,
    val overlay: OverlayPrefs = OverlayPrefs(),
    val capture: CapturePrefs = CapturePrefs(),
    val theme: ThemeMode = ThemeMode.DARK,
    val onboardingDone: Boolean = false,
)
