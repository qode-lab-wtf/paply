package com.paply.thoughts.display

import com.paply.thoughts.*
import com.paply.thoughts.ai.SpokenTime
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.processing.DueDate
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Every open task appears exactly once, preserving source order at equal dates. */
class TaskAgenda(
    thoughts: List<Thought>,
    now: Instant = Instant.now(),
    calendar: ZoneId = ZoneId.systemDefault(),
    doneWindowDays: Int = 7,
) {
    data class Item(val task: ThoughtTask, val thought: Thought) {
        val id
            get() = thought.id + "/" + task.id
    }

    enum class Group {
        overdue,
        today,
        upcoming,
        someday,
    }

    val overdue: List<Item>
    val today: List<Item>
    val upcoming: List<Item>
    val someday: List<Item>
    val recentlyDone: List<Item>
    val allDone: List<Item>

    init {
        val items =
            thoughts
                .filter { it.deletedAt == null }
                .flatMap { thought -> thought.tasks.map { Item(it, thought) } }
        val open = items.filter { !it.task.done }.groupBy { group(it.task.dueAt, now, calendar) }
        fun dated(group: Group) = open[group].orEmpty().sortedBy { it.task.dueAt }
        overdue = dated(Group.overdue)
        today = dated(Group.today)
        upcoming = dated(Group.upcoming)
        someday = open[Group.someday].orEmpty()
        allDone =
            items
                .filter { it.task.done }
                .sortedWith(compareByDescending { it.task.doneAt ?: Instant.MIN })
        val since =
            now.atZone(calendar)
                .toLocalDate()
                .minusDays(maxOf(0, doneWindowDays - 1).toLong())
                .atStartOfDay(calendar)
                .toInstant()
        recentlyDone = allDone.filter { (it.task.doneAt ?: Instant.MIN) >= since }
    }

    fun items(group: Group) =
        when (group) {
            Group.overdue -> overdue
            Group.today -> today
            Group.upcoming -> upcoming
            Group.someday -> someday
        }

    val openCount
        get() = overdue.size + today.size + upcoming.size + someday.size

    val urgentCount
        get() = overdue.size + today.size

    companion object {
        fun group(dueAt: Instant?, now: Instant, calendar: ZoneId = ZoneId.systemDefault()): Group {
            if (dueAt == null) return Group.someday
            val today = now.atZone(calendar).toLocalDate()
            return when {
                dueAt < today.atStartOfDay(calendar).toInstant() -> Group.overdue
                dueAt < today.plusDays(1).atStartOfDay(calendar).toInstant() -> Group.today
                else -> Group.upcoming
            }
        }

        fun urgentCount(
            thoughts: List<Thought>,
            now: Instant = Instant.now(),
            calendar: ZoneId = ZoneId.systemDefault(),
        ): Int {
            val tomorrow =
                now.atZone(calendar).toLocalDate().plusDays(1).atStartOfDay(calendar).toInstant()
            return thoughts
                .filter { it.deletedAt == null }
                .sumOf { thought ->
                    thought.tasks.count { !it.done && it.dueAt != null && it.dueAt < tomorrow }
                }
        }
    }
}

sealed interface TaskDueLabel {
    data class Wording(val text: String) : TaskDueLabel

    data class Today(val time: Instant?) : TaskDueLabel

    data class Tomorrow(val time: Instant?) : TaskDueLabel

    data class Yesterday(val time: Instant?) : TaskDueLabel

    data class Weekday(val date: Instant, val time: Instant?) : TaskDueLabel

    data class Date(val date: Instant, val time: Instant?) : TaskDueLabel

    companion object {
        fun make(
            task: ThoughtTask,
            recordedAt: Instant,
            now: Instant = Instant.now(),
            calendar: ZoneId = ZoneId.systemDefault(),
        ): TaskDueLabel? {
            val wording = task.dueHint?.let(TextForm::trim)?.takeIf { it.isNotEmpty() }
            val due = task.dueAt ?: return wording?.let(::Wording)
            if (
                wording != null &&
                    recordedAt.atZone(calendar).toLocalDate() == now.atZone(calendar).toLocalDate()
            )
                return Wording(wording)
            val time = spokenTime(task, calendar)
            return when (
                ChronoUnit.DAYS.between(
                    now.atZone(calendar).toLocalDate(),
                    due.atZone(calendar).toLocalDate(),
                )
            ) {
                0L -> Today(time)
                1L -> Tomorrow(time)
                -1L -> Yesterday(time)
                in 2L..6L -> Weekday(due, time)
                else -> Date(due, time)
            }
        }

        fun spokenTime(task: ThoughtTask, calendar: ZoneId = ZoneId.systemDefault()): Instant? {
            val due = task.dueAt ?: return null
            task.dueHasTime?.let {
                return if (it) due else null
            }
            val clock = DueDate.spokenClock(task.dueHint) ?: return null
            return due.takeIf { SpokenTime.matches(clock, due, calendar) }
        }
    }
}
