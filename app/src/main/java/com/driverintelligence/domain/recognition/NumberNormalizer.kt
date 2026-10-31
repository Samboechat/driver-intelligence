package com.driverintelligence.domain.recognition

/**
 * Normalização de números lidos por OCR em formatos brasileiros e internacionais.
 *
 *  "18,50"     → 18.5
 *  "1.234,56"  → 1234.56
 *  "8.4"       → 8.4
 *  "1,234.56"  → 1234.56
 *  "1.234"     → 1234 (só com [thousandsHint]; sem a dica vira 1.234)
 */
object NumberNormalizer {

    private val CONFUSABLE = mapOf('O' to '0', 'o' to '0', 'I' to '1', 'l' to '1', '|' to '1')

    fun parse(raw: String, thousandsHint: Boolean = false): Double? {
        val s = raw.trim().filterNot { it == ' ' || it == ' ' || it == ' ' }
        if (s.isEmpty() || s.none { it.isDigit() }) return null
        if (s.any { !(it.isDigit() || it == '.' || it == ',') }) return null

        val commas = s.count { it == ',' }
        val dots = s.count { it == '.' }
        val lastComma = s.lastIndexOf(',')
        val lastDot = s.lastIndexOf('.')

        val normalized = when {
            commas > 0 && dots > 0 ->
                if (lastComma > lastDot) s.replace(".", "").replace(',', '.') else s.replace(",", "")
            commas > 0 -> {
                val decimals = s.length - lastComma - 1
                when {
                    commas > 1 -> s.replace(",", "")
                    decimals == 3 && thousandsHint -> s.replace(",", "")
                    else -> s.replace(',', '.')
                }
            }
            dots > 0 -> {
                val decimals = s.length - lastDot - 1
                when {
                    dots > 1 -> s.replace(".", "")
                    decimals == 3 && thousandsHint -> s.replace(".", "")
                    else -> s
                }
            }
            else -> s
        }
        if (normalized.startsWith('.') || normalized.endsWith('.')) {
            return normalized.trim('.').toDoubleOrNull()?.takeIf { it.isFinite() }
        }
        return normalized.toDoubleOrNull()?.takeIf { it.isFinite() }
    }

    /**
     * Corrige confusões comuns do OCR (O→0, l→1...) apenas quando o caractere está colado a dígitos,
     * para não corromper palavras. Retorna o texto corrigido e o número de correções.
     */
    fun fixDigitConfusions(text: String): Pair<String, Int> {
        if (text.isEmpty()) return text to 0
        val chars = text.toCharArray()
        var fixes = 0
        for (i in chars.indices) {
            val replacement = CONFUSABLE[chars[i]] ?: continue
            val prev = chars.getOrNull(i - 1)
            val next = chars.getOrNull(i + 1)
            val prevDigit = prev != null && (prev.isDigit() || ((prev == ',' || prev == '.') && chars.getOrNull(i - 2)?.isDigit() == true))
            val nextDigit = next != null && (next.isDigit() || ((next == ',' || next == '.') && chars.getOrNull(i + 2)?.isDigit() == true))
            val prevIsLetter = prev != null && prev.isLetter() && CONFUSABLE[prev] == null
            val nextIsLetter = next != null && next.isLetter() && CONFUSABLE[next] == null
            val inNumber = (prevDigit && !nextIsLetter) || (nextDigit && !prevIsLetter) || (prevDigit && nextDigit)
            if (inNumber) {
                chars[i] = replacement
                fixes++
            }
        }
        return String(chars) to fixes
    }
}
