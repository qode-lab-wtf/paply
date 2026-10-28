@file:Suppress("DEPRECATION")

package com.paply.core

@Deprecated("Use WhisperSegment")
data class Segment(val text: String, val start: Double?, val end: Double?, val logprob: Double?) {
    internal fun core() = WhisperSegment(text, start, end, logprob)
}

@Deprecated("Use Transcription")
data class Transcript(val text: String, val language: String?, val segments: List<Segment>)

@Deprecated("Use ChatCompletion") data class Completion(val text: String, val finishReason: String?)

@Deprecated("Use DictationOutcome")
data class DictationResult(
    val raw: String,
    val text: String,
    val model: String?,
    val fallbackReason: String?,
)

internal fun Transcription.legacy() =
    Transcript(
        text?.trimmed().orEmpty(),
        language,
        segments.orEmpty().map { Segment(it.text.orEmpty(), it.start, it.end, it.avgLogprob) },
    )
