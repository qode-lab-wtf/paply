@file:kotlinx.serialization.UseSerializers(com.paply.thoughts.model.InstantMillisSerializer::class)

package com.paply.thoughts.store

import com.paply.thoughts.*
import java.time.Instant
import kotlinx.serialization.Serializable

class ThoughtStoreError(val code: Code) : java.io.IOException(code.name) {
    enum class Code {
        notImplemented,
        invalidID,
        notFound,
        sourceExists,
        unavailable,
    }
}

data class AIResultRecord(
    val result: StructureResult,
    val model: String? = null,
    val usage: TokenUsage? = null,
    val at: Instant = Instant.now(),
    val chosenTopic: TopicLabel? = null,
)

data class TopicLabel(val name: String, val icon: TopicIcon)

@Serializable
data class TopicsDocument(
    val schemaVersion: Int = 1,
    val rev: Int = 0,
    val topics: List<Topic>,
    val declinedMerges: List<List<String>> = emptyList(),
    val lastHygieneAt: Instant? = null,
)

@Serializable
data class StructureParts(
    val transcriptHash: String,
    val count: Int,
    val first: AIResultFile? = null,
    val rest: List<Part> = emptyList(),
    val lastCallAt: Instant? = null,
) {
    @Serializable
    data class Part(
        val cleanText: String?,
        val tasks: List<StoredTask>,
        val rejections: List<String>,
        val tokens: Int,
    )

    @Serializable
    data class StoredTask(val text: String, val quote: String, val dueHint: String? = null) {
        constructor(draft: TaskDraft) : this(draft.text, draft.quote, draft.dueHint)

        val draft
            get() = TaskDraft(text, quote, dueHint)
    }
}

@Serializable
data class AIResultFile(
    val schemaVersion: Int = 1,
    val title: String,
    val cleanText: String?,
    val topic: TopicDTO,
    val tasks: List<StructureParts.StoredTask>,
    val related: List<RelatedDraft>,
    val rejections: List<String>,
    val model: String? = null,
    val usage: TokenUsage? = null,
    val at: Instant,
) {
    @Serializable
    data class TopicDTO(
        val kind: String,
        val id: String? = null,
        val name: String? = null,
        val icon: TopicIcon? = null,
    )

    constructor(
        record: AIResultRecord,
    ) : this(
        title = record.result.title,
        cleanText = record.result.cleanText,
        topic =
            when (val t = record.result.topic) {
                is TopicDecision.Existing ->
                    TopicDTO("existing", t.id, record.chosenTopic?.name, record.chosenTopic?.icon)
                is TopicDecision.New -> TopicDTO("new", name = t.name, icon = t.icon)
                TopicDecision.None -> TopicDTO("none")
            },
        tasks = record.result.tasks.map { StructureParts.StoredTask(it) },
        related = record.result.related,
        rejections = record.result.rejections,
        model = record.model,
        usage = record.usage,
        at = record.at,
    )

    val record: AIResultRecord
        get() {
            val decision =
                when (topic.kind) {
                    "existing" -> topic.id?.let { TopicDecision.Existing(it) } ?: TopicDecision.None
                    "new" ->
                        topic.name?.let { TopicDecision.New(it, topic.icon ?: TopicIcon.sparkles) }
                            ?: TopicDecision.None
                    else -> TopicDecision.None
                }
            return AIResultRecord(
                StructureResult(
                    title,
                    cleanText,
                    decision,
                    tasks.map { it.draft },
                    related,
                    rejections,
                ),
                model,
                usage,
                at,
                if (topic.kind == "existing")
                    topic.name?.let { TopicLabel(it, topic.icon ?: TopicIcon.sparkles) }
                else null,
            )
        }
}
