package com.paply.core

import java.util.Locale
import kotlin.math.ceil

object GroqModels {
    const val whisper = "whisper-large-v3"
    const val whisperTurbo = "whisper-large-v3-turbo"
    const val polish = "qwen/qwen3.8-27b"
    const val polishFallback = "openai/gpt-oss-120b"

    fun select(available: List<String>, preferred: List<String>) = preferred.firstOrNull {
        it in available
    }

    data class ReasoningOptions(val format: String? = null, val effort: String? = null)

    fun reasoningOptions(model: String) =
        when {
            model.startsWith("openai/gpt-oss-") -> ReasoningOptions("hidden", "low")
            model.startsWith("qwen/") -> ReasoningOptions(effort = "none")
            else -> ReasoningOptions()
        }

    // Swift utf16.count, deliberately not Unicode scalar or grapheme count.
    fun polishTokenBudget(text: String) =
        (ceil(text.length / 3.0).toInt() * 2).coerceIn(4096, 32768)

    @Deprecated("Use polishTokenBudget") fun tokenBudget(text: String) = polishTokenBudget(text)

    fun languageCode(value: String?): String? {
        val raw =
            value?.trimmed()?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() } ?: return null
        return whisperLanguages[raw] ?: raw
    }

    val whisperLanguages =
        mapOf(
            "english" to "en",
            "german" to "de",
            "french" to "fr",
            "spanish" to "es",
            "italian" to "it",
            "portuguese" to "pt",
            "dutch" to "nl",
            "turkish" to "tr",
            "polish" to "pl",
            "russian" to "ru",
            "ukrainian" to "uk",
            "chinese" to "zh",
            "japanese" to "ja",
            "korean" to "ko",
            "arabic" to "ar",
            "hindi" to "hi",
            "swedish" to "sv",
            "danish" to "da",
            "norwegian" to "no",
            "nynorsk" to "nn",
            "finnish" to "fi",
            "czech" to "cs",
            "greek" to "el",
            "hungarian" to "hu",
            "romanian" to "ro",
            "hebrew" to "he",
            "vietnamese" to "vi",
            "thai" to "th",
            "indonesian" to "id",
            "malay" to "ms",
            "persian" to "fa",
            "catalan" to "ca",
            "croatian" to "hr",
            "serbian" to "sr",
            "slovak" to "sk",
            "slovenian" to "sl",
            "bulgarian" to "bg",
            "lithuanian" to "lt",
            "latvian" to "lv",
            "estonian" to "et",
            "tagalog" to "tl",
            "urdu" to "ur",
            "bengali" to "bn",
            "tamil" to "ta",
            "afrikaans" to "af",
            "welsh" to "cy",
            "icelandic" to "is",
            "bosnian" to "bs",
            "macedonian" to "mk",
            "galician" to "gl",
            "basque" to "eu",
            "swahili" to "sw",
            "albanian" to "sq",
            "cantonese" to "yue",
        )
}
