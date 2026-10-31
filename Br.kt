package com.driverintelligence.domain.util

import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Formatação pt-BR usada em toda a interface e no overlay. */
object Br {
    val locale: Locale = Locale.forLanguageTag("pt-BR")
    const val DASH = "—"

    fun money(value: Double?): String {
        if (value == null || !value.isFinite()) return DASH
        val formatted = String.format(locale, "%,.2f", abs(value))
        return if (value < -0.004) "−R$ $formatted" else "R$ $formatted"
    }

    fun perKm(value: Double?): String = if (value == null || !value.isFinite()) DASH else "${money(value)}/km"

    fun perHour(value: Double?): String = if (value == null || !value.isFinite()) DASH else "${money(value)}/h"

    fun km(value: Double?, decimals: Int = 1): String {
        if (value == null || !value.isFinite()) return DASH
        return String.format(locale, "%.${decimals}f km", value)
    }

    fun minutes(value: Double?): String {
        if (value == null || !value.isFinite()) return DASH
        val total = value.roundToInt()
        if (total < 60) return "$total min"
        val h = total / 60
        val m = total % 60
        return if (m == 0) "$h h" else String.format(locale, "%d h %02d min", h, m)
    }

    fun percent(fraction: Double?, decimals: Int = 0): String {
        if (fraction == null || !fraction.isFinite()) return DASH
        return String.format(locale, "%.${decimals}f%%", fraction * 100)
    }

    fun decimal(value: Double?, decimals: Int = 2): String {
        if (value == null || !value.isFinite()) return DASH
        return String.format(locale, "%.${decimals}f", value)
    }
}
