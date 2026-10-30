@file:UseSerializers(InstantMillisSerializer::class)

package com.paply.thoughts

import com.paply.core.PaplySettings
import com.paply.thoughts.model.InstantMillisSerializer
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.*

object ThoughtIDs {
    fun thought() = "s_" + hex32()

    fun topic() = "t_" + hex32()

    fun task() = "k_" + hex32()

    private fun hex32() = UUID.randomUUID().toString().replace("-", "")
}

@Serializable
enum class Owner {
    ai,
    user,
    system,
}

@Serializable
enum class ThoughtTrigger {
    control,
    shortcut,
    app,
    liveActivity,
    unknown,
}

@Serializable
enum class ThoughtState {
    recording,
    captured,
    transcribing,
    transcribed,
    structuring,
    done,
    waitingNetwork,
    waitingKey,
    waitingLimit,
    waitingBudget,
    needsAttention,
    empty,
}

@Serializable
enum class TopicIcon(val rawValue: String) {
    sparkles("sparkles"),
    lightbulb("lightbulb"),
    home("home"),
    code("code"),
    @SerialName("map-pin") mapPin("map-pin"),
    sun("sun"),
    moon("moon"),
    heart("heart"),
    coffee("coffee"),
    briefcase("briefcase"),
    calendar("calendar"),
    @SerialName("message-circle") messageCircle("message-circle"),
    book("book"),
    music("music"),
    camera("camera"),
    leaf("leaf"),
    flag("flag"),
    @SerialName("circle-help") circleHelp("circle-help"),
    pencil("pencil"),
    plane("plane"),
    wallet("wallet"),
    users("users"),
    list("list"),
    zap("zap");

    companion object {
        fun fromRaw(value: String) = entries.firstOrNull { it.rawValue == value }
    }
}

@Serializable
enum class LinkKind(val rawValue: String) {
    continues("continues"),
    @SerialName("same_matter") sameMatter("same_matter"),
    changes("changes");

    companion object {
        fun fromRaw(value: String) = entries.firstOrNull { it.rawValue == value }
    }
}

@Serializable
data class ThoughtTask(
    val id: String = ThoughtIDs.task(),
    val text: String,
    val quote: String? = null,
    val dueHint: String? = null,
    val dueAt: Instant? = null,
    val dueHasTime: Boolean? = null,
    val done: Boolean = false,
    val doneAt: Instant? = null,
    val owner: Owner,
    val createdAt: Instant = Instant.now(),
)

@Serializable
data class ThoughtLink(
    val target: String,
    val kind: LinkKind,
    val reason: String,
    val origin: Owner,
    val createdAt: Instant = Instant.now(),
)

/** Immutable snapshots retain Swift value semantics across store and coroutine boundaries. */
@Serializable
data class Thought(
    val schemaVersion: Int = 1,
    val id: String = ThoughtIDs.thought(),
    val kind: String = "voice",
    val createdAt: Instant = Instant.now(),
    val durationMs: Int = 0,
    val trigger: ThoughtTrigger,
    val state: ThoughtState,
    val title: String? = null,
    val titleOwner: Owner = Owner.system,
    val text: String? = null,
    val textOwner: Owner = Owner.system,
    val textIsRaw: Boolean = false,
    val topicId: String? = null,
    val topicOwner: Owner = Owner.system,
    val tasks: List<ThoughtTask> = emptyList(),
    val links: List<ThoughtLink> = emptyList(),
    val languages: List<String> = emptyList(),
    val keywords: List<String> = emptyList(),
    val ai: AIInfo? = null,
    val audio: AudioInfo? = null,
    val status: Status = Status(),
    val rev: Int = 1,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
) {
    @Serializable
    data class AIInfo(
        val model: String,
        val promptVersion: Int,
        val tokens: Int,
        val at: Instant,
        val rejections: List<String> = emptyList(),
    )

    @Serializable data class AudioInfo(val file: String)

    @Serializable
    data class Status(
        val message: String? = null,
        val attempts: Int = 0,
        val retryAt: Instant? = null,
    )
}

@Serializable
data class ThoughtSource(
    val text: String,
    val sentences: List<Sentence>,
    val model: String,
    val createdAt: Instant,
    val languages: List<String>,
    val audioSeconds: Double,
) {
    @Serializable data class Sentence(val id: String, val text: String)
}

@Serializable
data class Topic(
    val id: String = ThoughtIDs.topic(),
    val title: String,
    val icon: TopicIcon,
    val owner: Owner,
    val createdAt: Instant = Instant.now(),
    val mergedInto: String? = null,
    val note: String? = null,
) {
    val describedNote
        get() = normalizedNote(note)

    val isUserDefined
        get() = owner == Owner.user || describedNote != null

    companion object {
        const val maxNoteLength = 200

        fun normalizedNote(note: String?): String? =
            note
                ?.let {
                    com.paply.thoughts.model.TextForm.trim(it)
                }
                ?.takeIf { it.isNotEmpty() }
                ?.let { com.paply.thoughts.model.TextForm.prefix(it, maxNoteLength) }
                ?.let { com.paply.thoughts.model.TextForm.trim(it) }
    }
}

data class TopicIndexEntry(
    val topicID: String,
    val name: String,
    val count: Int,
    val hint: List<String>,
    val about: String? = null,
    val mentioned: Boolean = false,
)

data class CandidateEntry(
    val thoughtID: String,
    val title: String,
    val topicID: String?,
    val `when`: String,
    val excerpt: String,
    val localScore: Double,
)

data class StructureInput(
    val transcript: String,
    val sentences: List<ThoughtSource.Sentence>,
    val spokenLanguages: List<String>,
    val uiLanguage: String,
    val vocabulary: String,
    val topics: List<TopicIndexEntry>,
    val topicsFull: Boolean,
    val candidates: List<CandidateEntry>,
    val part: Part? = null,
    val reasoningEffort: String = "low",
    val recordedAt: Instant? = null,
) {
    data class Part(val index: Int, val count: Int)
}

sealed interface TopicDecision {
    data class Existing(val id: String) : TopicDecision

    data class New(val name: String, val icon: TopicIcon) : TopicDecision

    data object None : TopicDecision
}

@Serializable data class TaskDraft(val text: String, val quote: String, val dueHint: String? = null)

@Serializable data class RelatedDraft(val thoughtID: String, val kind: LinkKind, val reason: String)

data class StructureResult(
    val title: String,
    val cleanText: String?,
    val topic: TopicDecision,
    val tasks: List<TaskDraft>,
    val related: List<RelatedDraft>,
    val rejections: List<String> = emptyList(),
)

@Serializable data class TokenUsage(val prompt: Int, val completion: Int, val total: Int)

sealed interface StructureOutcome {
    data class Success(val result: StructureResult, val model: String, val usage: TokenUsage) :
        StructureOutcome

    data class Wait(val state: ThoughtState, val retryAt: Instant?, val message: String) :
        StructureOutcome

    data class Unusable(val code: String) : StructureOutcome
}

fun interface ThoughtStructuring {
    suspend fun structure(input: StructureInput, apiKey: String): StructureOutcome
}

/** Local/Map/Display (part B) implements this boundary; no ranking guessed in this module. */
interface CandidateFinding {
    data class TopicIndex(val entries: List<TopicIndexEntry>, val full: Boolean)

    suspend fun topicIndex(forText: String, languages: List<String>): TopicIndex

    suspend fun candidates(
        forText: String,
        languages: List<String>,
        excluding: String,
    ): List<CandidateEntry>

    suspend fun candidates(
        forText: String,
        languages: List<String>,
        excluding: String,
        relativeTo: Instant,
    ): List<CandidateEntry> = candidates(forText, languages, excluding)

    suspend fun didChange(thought: Thought)
}

sealed interface ProcessorEvent {
    data class Processing(val id: String) : ProcessorEvent

    data class Saved(val id: String, val topicTitle: String?, val topicIcon: TopicIcon?) :
        ProcessorEvent

    data class Waiting(val id: String, val state: ThoughtState, val message: String) :
        ProcessorEvent

    data class Empty(val id: String) : ProcessorEvent

    data class Failed(val id: String, val message: String) : ProcessorEvent
}

data class ProcessorEnvironment(
    val apiKey: suspend () -> String?,
    val isOnline: suspend () -> Boolean,
    val isDictationBusy: suspend () -> Boolean,
    val settings: suspend () -> PaplySettings,
    val uiLanguage: String,
)

/**
 * Part B supplies the local keyword extraction; no candidate/ranking implementation is bundled
 * here.
 */
fun interface KeywordFinding {
    suspend fun keywords(forText: String, language: String?): List<String>
}

/**
 * Swift TopicIndex.summaries boundary. Active means user-owned or at least two undeleted members.
 */
fun interface TopicSummarizing {
    data class Summary(
        val topic: Topic,
        val count: Int,
        val lastActivity: Instant?,
        val isActive: Boolean,
        val memberIDs: List<String>,
    )

    fun summaries(topics: List<Topic>, thoughts: List<Thought>): List<Summary>
}
