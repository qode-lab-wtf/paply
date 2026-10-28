package com.paply.thoughts.model

import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class TopicSuggestion(val a: String, val b: String, val name: String?, val reason: String) {
    val id
        get() = "$a|$b"
}

data class SearchHit(
    val thoughtID: String,
    val field: Field,
    val snippet: String,
    /** UTF-16 offsets with inclusive ends, as Kotlin IntRange; adapt NSRange.length accordingly. */
    val ranges: List<IntRange> = emptyList(),
    val score: Double = 0.0,
) {
    enum class Field {
        title,
        text,
        raw,
        task,
        topic,
    }

    val id
        get() = thoughtID
}

data class UndoToken(val id: String = UUID.randomUUID().toString())

data class ThoughtsUsage(
    val tokens: Int,
    val audioSeconds: Int,
    val requests: Int,
    val dailyTokens: Int,
)
