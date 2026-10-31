package com.paply.core

internal object LanguageGuard {
    const val shortSpeechSeconds = 5.0

    fun primary(chosen: String?, userLanguages: List<String>, device: String?): String? {
        val codes = userLanguages.map(CodeSwitchPrimer::baseCode).filter(String::isNotEmpty)
        for (candidate in listOfNotNull(chosen, device)) {
            val code = CodeSwitchPrimer.baseCode(candidate)
            if (code in codes) return code
        }
        return codes.firstOrNull()
    }

    const val checkGap = 0.15

    fun expected(previous: String?, primary: String?): String? =
        listOfNotNull(previous, primary).map(CodeSwitchPrimer::baseCode).firstOrNull { it.isNotEmpty() }

    fun needsCheck(expected: String?, detected: String?, users: List<String>, spoken: Double): Boolean {
        val e = expected?.let(CodeSwitchPrimer::baseCode).orEmpty()
        val d = detected?.let(CodeSwitchPrimer::baseCode).orEmpty()
        return e.isNotEmpty() && d.isNotEmpty() && e != d &&
            (spoken <= shortSpeechSeconds || d !in users.map(CodeSwitchPrimer::baseCode))
    }

    /** Raw response only: filtering must not bias language confidence. */
    fun confidence(response: Transcription): Double? {
        val segments = response.segments?.takeIf { it.isNotEmpty() } ?: return null
        var total = 0.0
        var weights = 0.0
        for (segment in segments) {
            val lp = segment.avgLogprob?.takeIf { it.isFinite() } ?: return null
            val duration = (segment.end ?: 0.0) - (segment.start ?: 0.0)
            val weight = maxOf(0.01, duration.takeIf { it.isFinite() } ?: 0.0)
            total += lp * weight
            weights += weight
        }
        return total / weights
    }

    private fun normalized(text: String): String =
        text.lowercase(java.util.Locale.ROOT).replace(Regex("\\s+"), "")
            .replace(Regex("^[\\p{P}]+|[\\p{P}]+$"), "")

    fun chooseExpected(detected: Transcription, checked: Transcription?): Boolean {
        if (checked == null) return false
        if (detected.text != null && checked.text != null &&
            normalized(detected.text) == normalized(checked.text)) return true
        val first = confidence(detected) ?: return false
        val second = confidence(checked) ?: return false
        return first - second < checkGap
    }
}
