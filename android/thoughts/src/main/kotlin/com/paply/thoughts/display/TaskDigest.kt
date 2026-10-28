package com.paply.thoughts.display

import com.paply.thoughts.*
import java.time.Instant
import java.time.ZoneId

data class TaskKey(val thoughtID: String, val taskID: String)

class TaskDigest(
    thoughts: List<Thought>,
    pending: Map<TaskKey, Instant> = emptyMap(),
    now: Instant = Instant.now(),
    calendar: ZoneId = ZoneId.systemDefault(),
    limit: Int = 5,
) {
    data class Item(
        val thoughtID: String,
        val taskID: String,
        val text: String,
        val dueAt: Instant?,
        val hasTime: Boolean,
        val topicID: String?,
    )

    val openCount: Int
    val urgentCount: Int
    val doneToday: List<Instant>
    val dueDates: List<Instant>
    val items: List<Item>

    init {
        val patched =
            if (pending.isEmpty()) thoughts
            else
                thoughts.map { thought ->
                    thought.copy(
                        tasks =
                            thought.tasks.map { task ->
                                val at = pending[TaskKey(thought.id, task.id)]
                                if (!task.done && at != null) task.copy(done = true, doneAt = at)
                                else task
                            },
                    )
                }
        val agenda = TaskAgenda(patched, now, calendar, doneWindowDays = 1)
        val dated = agenda.overdue + agenda.today + agenda.upcoming
        openCount = agenda.openCount
        urgentCount = agenda.urgentCount
        dueDates = dated.mapNotNull { it.task.dueAt }
        val start = now.atZone(calendar).toLocalDate().atStartOfDay(calendar).toInstant()
        doneToday =
            agenda.recentlyDone.mapNotNull { it.task.doneAt }.filter { it >= start }.sorted()
        items =
            (dated + agenda.someday).take(maxOf(0, limit)).map {
                Item(
                    it.thought.id,
                    it.task.id,
                    it.task.text,
                    it.task.dueAt,
                    TaskDueLabel.spokenTime(it.task, calendar) != null,
                    it.thought.topicId,
                )
            }
    }

    override fun equals(other: Any?) =
        other is TaskDigest &&
            openCount == other.openCount &&
            urgentCount == other.urgentCount &&
            doneToday == other.doneToday &&
            dueDates == other.dueDates &&
            items == other.items

    override fun hashCode() = listOf(openCount, urgentCount, doneToday, dueDates, items).hashCode()
}

/** Plan against a fully loaded store. Settle requests only after applying them durably. */
object TaskCompletionPlan {
    data class Request(val id: String, val key: TaskKey, val at: Instant)

    data class Result(
        val apply: List<Request>,
        val ignored: List<String>,
        val settled: List<String>,
    )

    fun make(requests: List<Request>, thoughts: List<Thought>): Result {
        val byID = thoughts.distinctBy { it.id }.associateBy { it.id }
        val seen = mutableSetOf<TaskKey>()
        val apply = mutableListOf<Request>()
        val ignored = mutableListOf<String>()
        for (request in requests.sortedWith(compareBy<Request> { it.at }.thenBy { it.id })) {
            val thought = byID[request.key.thoughtID]
            val task = thought?.tasks?.firstOrNull { it.id == request.key.taskID }
            if (
                seen.add(request.key) &&
                    thought != null &&
                    thought.deletedAt == null &&
                    task != null &&
                    !task.done
            )
                apply.add(request)
            else ignored.add(request.id)
        }
        return Result(apply, ignored, requests.map { it.id })
    }
}
