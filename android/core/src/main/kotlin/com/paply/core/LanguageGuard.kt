package com.paply.core

internal object LanguageGuard {
    fun whisperCode(value: String): String = when (val code = CodeSwitchPrimer.baseCode(value)) {
        "nb" -> "no"
        "fil" -> "tl"
        "iw" -> "he"
        "in" -> "id"
        "ji" -> "yi"
        "jw" -> "jv"
        else -> code
    }

    fun checkTimeoutMs(firstMs: Double): Long = (2 * firstMs + 5000).coerceIn(5000.0, 60000.0).toLong()

    const val shortSpeechSeconds = 5.0

    fun primary(chosen: String?, userLanguages: List<String>, device: String?): String? {
        val codes = userLanguages.map(::whisperCode).filter(String::isNotEmpty)
        for (candidate in listOfNotNull(chosen, device)) {
            val code = whisperCode(candidate)
            if (code in codes) return code
        }
        return codes.firstOrNull()
    }

    const val checkGap = 0.15

    fun expected(previous: String?, primary: String?): String? =
        listOfNotNull(previous, primary).map(::whisperCode).firstOrNull { it.isNotEmpty() }

    fun needsCheck(expected: String?, detected: String?, users: List<String>, spoken: Double): Boolean {
        val e = expected?.let(::whisperCode).orEmpty()
        val d = detected?.let(::whisperCode).orEmpty()
        return e.isNotEmpty() && d.isNotEmpty() && e != d &&
            (spoken <= shortSpeechSeconds || d !in users.map(::whisperCode))
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
        text.lowercase(java.util.Locale.ROOT).replace(Regex("\\s+"), " ")
            .replace(Regex("^[\\p{P}]+|[\\p{P}]+$"), "")

    fun chooseExpected(detected: Transcription, checked: Transcription?, spoken: Double = 0.0): Boolean {
        if (checked == null) return false
        if (detected.text != null && checked.text != null &&
            normalized(detected.text) == normalized(checked.text)) return true
        val first = confidence(detected) ?: return false
        val second = confidence(checked) ?: return false
        if (spoken > shortSpeechSeconds) return second - first >= checkGap
        return first - second < checkGap
    }
}
