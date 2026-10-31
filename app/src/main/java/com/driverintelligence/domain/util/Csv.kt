package com.driverintelligence.domain.util

/**
 * Gerador de CSV compatível com Excel/LibreOffice em pt-BR:
 * separador ";" (a vírgula é o separador decimal) e BOM UTF-8 para acentuação correta.
 */
object Csv {
    const val BOM = "﻿"

    fun write(header: List<String>, rows: List<List<String?>>, delimiter: Char = ';', withBom: Boolean = true): String {
        val sb = StringBuilder()
        if (withBom) sb.append(BOM)
        sb.append(header.joinToString(delimiter.toString()) { escape(it, delimiter) }).append("\r\n")
        rows.forEach { row ->
            sb.append(row.joinToString(delimiter.toString()) { escape(it.orEmpty(), delimiter) }).append("\r\n")
        }
        return sb.toString()
    }

    fun escape(value: String, delimiter: Char = ';'): String {
        // Evita injeção de fórmulas ao abrir em planilhas.
        val safe = if (value.isNotEmpty() && value[0] in "=+-@" && value.toDoubleOrNull() == null && !value.matches(Regex("-?\\d+([.,]\\d+)?"))) "'$value" else value
        val needsQuotes = safe.any { it == delimiter || it == '"' || it == '\n' || it == '\r' }
        return if (needsQuotes) "\"" + safe.replace("\"", "\"\"") + "\"" else safe
    }
}
