@file:kotlinx.serialization.UseSerializers(
    com.paply.thoughts.display.FoundationDateSerializer::class,
)

package com.paply.thoughts.display

import com.paply.thoughts.*
import com.paply.thoughts.model.TaskReminderID
import com.paply.thoughts.model.TextForm
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.roundToLong
import kotlinx.serialization.Serializable

data class TaskReminder(
    val id: String,
    val thoughtID: String,
    val taskID: String,
    val fireAt: Instant,
    val dueAt: Instant,
    val snoozed: Boolean,
    val title: String,
    val body: String,
    val threadID: String,
) {
    val signature: String
        get() =
            listOf(
                    roundedSeconds(fireAt),
                    roundedSeconds(dueAt),
                    if (snoozed) "s" else "-",
                    threadID,
                    title,
                    body,
                )
                .joinToString("|")

    private fun roundedSeconds(date: Instant): Long {
        val value = date.epochSecond + date.nano / 1e9
        return if (value < 0) -(-value).roundToLong() else value.roundToLong()
    }
}

/** Pure notification selection/diff/snooze rules. Android owns scheduling and permissions. */
object TaskReminderPlan {
    const val limit = 50
    const val snoozeInterval = 3600L
    const val prefix = "task/"

    @Serializable data class Snooze(val fireAt: Instant, val dueAt: Instant)

    data class Changes(
        val schedule: List<TaskReminder> = emptyList(),
        val remove: List<String> = emptyList(),
        val unchanged: Int = 0,
    ) {
        val isEmpty
            get() = schedule.isEmpty() && remove.isEmpty()
    }

    fun identifier(thoughtID: String, taskID: String) = TaskReminderID.identifier(thoughtID, taskID)

    fun parse(identifier: String): TaskKey? {
        if (!identifier.startsWith(prefix)) return null
        val parts = identifier.removePrefix(prefix).split('/')
        return if (parts.size == 2 && parts.all { it.isNotEmpty() }) TaskKey(parts[0], parts[1])
        else null
    }

    fun reminderTime(
        task: ThoughtTask,
        thought: Thought,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): Instant? =
        if (thought.deletedAt == null && !task.done) TaskDueLabel.spokenTime(task, calendar)
        else null

    fun reminders(
        thoughts: List<Thought>,
        topic: (Thought) -> Topic?,
        snoozes: Map<String, Snooze> = emptyMap(),
        now: Instant,
        limit: Int = this.limit,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): List<TaskReminder> {
        val result = mutableListOf<TaskReminder>()
        val seen = mutableSetOf<String>()
        for (thought in thoughts) for (task in thought.tasks) {
            val due = reminderTime(task, thought, calendar) ?: continue
            val id = identifier(thought.id, task.id)
            if (!seen.add(id)) continue
            val snooze = snoozes[id]?.takeIf { applies(it, due, now) }
            val fireAt = snooze?.fireAt ?: due.takeIf { it > now } ?: continue
            val resolved = topic(thought)
            result.add(
                TaskReminder(
                    id,
                    thought.id,
                    task.id,
                    fireAt,
                    due,
                    snooze != null,
                    title(task),
                    body(thought, resolved),
                    threadID(resolved),
                ),
            )
        }
        return result
            .sortedWith(compareBy<TaskReminder> { it.fireAt }.thenBy { it.id })
            .take(maxOf(0, limit))
    }

    fun hasUpcoming(
        thoughts: List<Thought>,
        now: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
    ) = thoughts.any { thought ->
        thought.tasks.any { task ->
            reminderTime(task, thought, calendar)?.let { it > now } == true
        }
    }

    fun changes(
        current: Map<String, String>,
        desired: List<TaskReminder>,
        salt: String = "",
    ): Changes {
        val wanted = desired.map { it.id }.toSet()
        val unchanged = desired.count { current[it.id] == it.signature + salt }
        return Changes(
            desired.filter { current[it.id] != it.signature + salt },
            current.keys.filter { it !in wanted }.sorted(),
            unchanged,
        )
    }

    fun stale(delivered: List<String>, thoughts: List<Thought>): List<String> {
        val open =
            thoughts
                .filter { it.deletedAt == null }
                .flatMap { thought ->
                    thought.tasks.filter { !it.done }.map { identifier(thought.id, it.id) }
                }
                .toSet()
        return delivered.filter { parse(it) != null && it !in open }
    }

    fun removableDelivered(ids: List<String>, thoughts: List<Thought>, featureOn: Boolean) =
        if (featureOn) stale(ids, thoughts) else ids.filter { parse(it) != null }

    data class SnoozeFacts(
        val thoughts: List<Thought>?,
        val queued: Boolean,
        val inSnapshot: Boolean?,
        val locked: Boolean,
    )

    fun maySnooze(thoughtID: String, taskID: String, facts: SnoozeFacts): Boolean {
        if (facts.queued) return false
        facts.thoughts?.let { thoughts ->
            val thought = thoughts.firstOrNull { it.id == thoughtID } ?: return false
            if (thought.deletedAt != null) return false
            val task = thought.tasks.firstOrNull { it.id == taskID } ?: return false
            return !task.done
        }
        if (facts.locked) return true
        return facts.inSnapshot == true
    }

    fun snoozed(from: Instant) = Instant.ofEpochSecond(from.epochSecond + snoozeInterval)

    internal fun applies(snooze: Snooze, due: Instant, now: Instant) =
        abs(secondsBetween(snooze.dueAt, due)) < 1 && snooze.fireAt > now

    fun keptSnoozes(
        stored: Map<String, Snooze>,
        pending: Map<String, Snooze> = emptyMap(),
        thoughts: List<Thought>?,
        now: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): Map<String, Snooze> {
        val merged = stored.toMutableMap()
        for ((id, snooze) in pending) if (merged[id]?.let { snooze.fireAt > it.fireAt } != false)
            merged[id] = snooze
        val live = merged.filter { parse(it.key) != null && it.value.fireAt > now }
        if (thoughts == null) return live
        val due = mutableMapOf<String, Instant>()
        for (thought in thoughts) for (task in thought.tasks) {
            val id = identifier(thought.id, task.id)
            if (id in due || id !in live) continue
            reminderTime(task, thought, calendar)?.let { due[id] = it }
        }
        return live.filter { (id, snooze) -> due[id]?.let { applies(snooze, it, now) } == true }
    }

    internal fun title(task: ThoughtTask) = TextForm.trim(task.text)

    internal fun body(thought: Thought, topic: Topic?) =
        listOfNotNull(topic?.title, thought.title)
            .map(TextForm::trim)
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

    internal fun threadID(topic: Topic?) = "paply.topic." + (topic?.id ?: "none")

    internal fun secondsBetween(from: Instant, to: Instant) =
        (to.epochSecond - from.epochSecond).toDouble() + (to.nano - from.nano) / 1e9
}
