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

    data class Request(val language: String?, val source: LanguageSource)

    fun firstRequest(
        fixed: String?,
        primary: String?,
        previous: String?,
        userLanguages: List<String>,
        spokenSeconds: Double,
    ): Request {
        fixed?.trimmed()?.takeIf(String::isNotEmpty)?.let {
            return Request(it, LanguageSource.fixed)
        }
        if (!(spokenSeconds <= shortSpeechSeconds)) return Request(null, LanguageSource.auto)
        val codes = userLanguages.map(CodeSwitchPrimer::baseCode)
        previous
            ?.let(CodeSwitchPrimer::baseCode)
            ?.takeIf { it in codes }
            ?.let {
                return Request(it, LanguageSource.short)
            }
        if (primary != null) return Request(primary, LanguageSource.short)
        return Request(null, LanguageSource.auto)
    }

    fun redoLanguage(detected: String?, primary: String?, userLanguages: List<String>): String? {
        val code = detected?.let(CodeSwitchPrimer::baseCode) ?: return null
        return primary?.takeIf {
            code.isNotEmpty() &&
                code != it &&
                code !in userLanguages.map(CodeSwitchPrimer::baseCode)
        }
    }
}
