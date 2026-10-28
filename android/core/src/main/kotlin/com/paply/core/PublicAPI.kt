package com.paply.core

import java.util.Locale
import kotlinx.serialization.json.*

/** Snapshot of one session. Secrets are obtained at session start and never serialized. */
data class DictationConfiguration(
    val keyProvider: () -> String,
    val primaryLanguage: String? = null,
    val spokenLanguages: List<String> = emptyList(),
    val vocabulary: String = "",
    val transcriptionModel: String = GroqModels.whisper,
    val chunkedUpload: Boolean = true,
    val language: String? = null,
    val polishModel: String = GroqModels.polish,
    val fallbackPolishModel: String = GroqModels.polishFallback,
    val deviceLanguages: List<String> = listOf(Locale.getDefault().toLanguageTag()),
) {
    fun settings() =
        PaplySettings(
            transcriptionModel,
            polishModel,
            fallbackPolishModel,
            vocabulary,
            language,
            chunkedUpload,
            spokenLanguages.toList(),
            primaryLanguage,
        )
}

data class PaplySettings(
    var transcriptionModel: String = GroqModels.whisper,
    var polishModel: String = GroqModels.polish,
    var fallbackPolishModel: String = GroqModels.polishFallback,
    var vocabulary: String = "",
    var language: String? = null,
    var chunkedUpload: Boolean = true,
    var spokenLanguages: List<String> = emptyList(),
    var primaryLanguage: String? = null,
) {
    fun toJson() = buildJsonObject {
        put("transcriptionModel", transcriptionModel)
        put("polishModel", polishModel)
        put("fallbackPolishModel", fallbackPolishModel)
        put("vocabulary", vocabulary)
        language?.let { put("language", it) }
        put("chunkedUpload", chunkedUpload)
        put("spokenLanguages", JsonArray(spokenLanguages.map(::JsonPrimitive)))
        primaryLanguage?.let { put("primaryLanguage", it) }
    }
        .toString()

    companion object {
        fun fromJson(json: String): PaplySettings {
            val o = Json.parseToJsonElement(json).jsonObject
            val d = PaplySettings()
            return PaplySettings(
                o.string("transcriptionModel") ?: d.transcriptionModel,
                o.string("polishModel") ?: d.polishModel,
                o.string("fallbackPolishModel") ?: d.fallbackPolishModel,
                o.string("vocabulary") ?: "",
                o.string("language"),
                (o["chunkedUpload"] as? JsonPrimitive)?.booleanOrNull ?: true,
                (o["spokenLanguages"] as? JsonArray)?.map { it.jsonPrimitive.content }.orEmpty(),
                o.string("primaryLanguage"),
            )
        }
    }
}

data class PipelineOptions(
    val uploadFormat: UploadFormat = UploadFormat.flac,
    val codeSwitchPrimer: Boolean = true,
    val polish: Boolean = true,
    val strictPolishCheck: Boolean = true,
) {
    enum class UploadFormat {
        flac,
        wav,
    }
}

data class DictationTimings(
    val transcriptionDoneMs: Double? = null,
    val polishDoneMs: Double? = null,
    val totalMs: Double? = null,
    val chunkCount: Int = 0,
    val uploadedBytes: Int = 0,
    val audioSeconds: Double = 0.0,
)

data class DictationOutcome(
    val text: String = "",
    val raw: String = "",
    val polished: String? = null,
    val polishRejection: String? = null,
    val errorMessage: String? = null,
    val languages: List<String> = emptyList(),
    val timings: DictationTimings = DictationTimings(),
    val polishError: String? = null,
    val polishModel: String? = null,
    val noSpeech: Boolean = false,
    val languageSources: List<String> = emptyList(),
    val error: DictationError? = null,
) {
    companion object {
        fun fromJson(json: String): DictationOutcome {
            val o = Json.parseToJsonElement(json).jsonObject
            fun strings(key: String) =
                (o[key] as? JsonArray)?.map { it.jsonPrimitive.content }.orEmpty()
            val t = o["timings"] as? JsonObject
            val timings =
                if (t == null) DictationTimings()
                else
                    DictationTimings(
                        t.number("transcriptionDoneMs"),
                        t.number("polishDoneMs"),
                        t.number("totalMs"),
                        t.number("chunkCount")?.toInt() ?: 0,
                        t.number("uploadedBytes")?.toInt() ?: 0,
                        t.number("audioSeconds") ?: 0.0,
                    )
            return DictationOutcome(
                o.string("text") ?: "",
                o.string("raw") ?: "",
                o.string("polished"),
                o.string("polishRejection"),
                o.string("errorMessage"),
                strings("languages"),
                timings,
                o.string("polishError"),
                o.string("polishModel"),
                (o["noSpeech"] as? JsonPrimitive)?.booleanOrNull ?: false,
                strings("languageSources"),
                o.string("error")?.let { value ->
                    DictationError.entries.firstOrNull { it.name == value }
                },
            )
        }
    }

    fun toJson() = buildJsonObject {
        put("text", text)
        put("raw", raw)
        polished?.let { put("polished", it) }
        polishRejection?.let { put("polishRejection", it) }
        errorMessage?.let { put("errorMessage", it) }
        put("languages", JsonArray(languages.map(::JsonPrimitive)))
        put("languageSources", JsonArray(languageSources.map(::JsonPrimitive)))
        polishError?.let { put("polishError", it) }
        polishModel?.let { put("polishModel", it) }
        put("noSpeech", noSpeech)
        error?.let { put("error", it.name) }
        put(
            "timings",
            buildJsonObject {
                timings.transcriptionDoneMs?.let { put("transcriptionDoneMs", it) }
                timings.polishDoneMs?.let { put("polishDoneMs", it) }
                timings.totalMs?.let { put("totalMs", it) }
                put("chunkCount", timings.chunkCount)
                put("uploadedBytes", timings.uploadedBytes)
                put("audioSeconds", timings.audioSeconds)
            },
        )
    }
        .toString()

    val language
        get() = languages.firstOrNull()

    val polishFailure
        get() = PolishFailureCode.entries.firstOrNull { it.rawValue == polishError }

    val polishRejectionCode
        get() = PolishRejectionCode.entries.firstOrNull { it.name == polishRejection }
}

enum class DictationError {
    unauthorized,
    rateLimited,
    serverError,
    requestRejected,
    network,
    invalidResponse,
    cancelled,
    audioUnavailable,
}

enum class DictationState {
    recording,
    transcribing,
    polishing,
    finished,
    failed,
    cancelled,
}

data class DictationStatus(
    val state: DictationState,
    val speechDetected: Boolean = false,
    val levelDbfs: Double = -120.0,
)

enum class PolishFailureCode(val rawValue: String) {
    disabled("disabled"),
    modelUnavailable("model-unavailable"),
    rateLimited("rate-limited"),
    unauthorized("unauthorized"),
    serverError("server-error"),
    requestRejected("request-rejected"),
    network("network"),
    invalidResponse("invalid-response"),
    cancelled("cancelled"),
}

enum class LanguageSource(val rawValue: String) {
    auto("auto"),
    short("short"),
    redo("redo"),
    redoFailed("redo-failed"),
    fixed("fixed"),
}

enum class PolishRejectionCode {
    empty,
    meta,
    length,
    content,
    negation,
    digits,
    replaced,
    inserted,
    added,
    truncated,
}

data class WhisperSegment(
    val text: String? = null,
    val start: Double? = null,
    val end: Double? = null,
    val avgLogprob: Double? = null,
    val noSpeechProb: Double? = null,
    val compressionRatio: Double? = null,
)

data class Transcription(
    val text: String? = null,
    val language: String? = null,
    val duration: Double? = null,
    val segments: List<WhisperSegment>? = null,
)

data class ChatCompletion(val content: String? = null, val finishReason: String? = null)

internal fun JsonObject.string(key: String): String? =
    (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

internal fun JsonObject.number(key: String): Double? =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
