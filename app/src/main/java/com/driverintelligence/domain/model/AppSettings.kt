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
    /** Escala do overlay inteiro (texto e tamanho): 1,0 normal · 1,15 grande · 1,3 extra. */
    val textScale: Float = 1f,
    /** Mostra o faturamento do dia e a meta no rodapé do overlay. */
    val showDailyProgress: Boolean = true,
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

/** Inteligência de corrida: tempo realista e acompanhamento do aceite/recusa. */
data class IntelligencePrefs(
    /** Multiplicador padrão do tempo de busca até haver corridas medidas suficientes. */
    val defaultPickupFactor: Double = 1.35,
    /** Multiplicador padrão do tempo de viagem. */
    val defaultTripFactor: Double = 1.15,
    /** Classificar as ofertas pelo tempo realista. */
    val useRealisticTime: Boolean = true,
    /** Detectar aceite/recusa e acompanhar a corrida pela tela. */
    val autoTrack: Boolean = true,
    /** Registrar como realizada, com tempos reais, a corrida concluída detectada. */
    val autoRegister: Boolean = true,
)

data class AppSettings(
    val goals: Goals = Goals(),
    val scoring: ScoringConfig = ScoringConfig(),
    val emptyReturn: EmptyReturnScenario = EmptyReturnScenario.None,
    val overlay: OverlayPrefs = OverlayPrefs(),
    val capture: CapturePrefs = CapturePrefs(),
    val intelligence: IntelligencePrefs = IntelligencePrefs(),
    val theme: ThemeMode = ThemeMode.DARK,
    val onboardingDone: Boolean = false,
)
