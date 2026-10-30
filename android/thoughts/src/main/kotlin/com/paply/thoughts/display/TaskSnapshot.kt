@file:kotlinx.serialization.UseSerializers(
    com.paply.thoughts.display.FoundationDateSerializer::class,
)

package com.paply.thoughts.display

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.abs
import kotlinx.serialization.Serializable

object TaskWidgetSettings {
    const val requireAuthKey = "paply.tasks.requireAuth"

    fun requiresAuth(defaults: Map<String, Any?>?) =
        defaults?.get(requireAuthKey) as? Boolean ?: true
}

@Serializable
data class TaskSnapshot(
    val version: Int = formatVersion,
    val generatedAt: Instant,
    val openCount: Int,
    val urgentCount: Int,
    val doneTodayAt: List<Instant>,
    val dueDates: List<Instant>,
    val items: List<Item>,
) {
    @Serializable
    data class Item(
        val thoughtID: String,
        val taskID: String,
        val text: String,
        val dueAt: Instant?,
        val hasTime: Boolean,
        val topicTitle: String? = null,
        val topicColor: Long? = null,
        val topicSymbol: String? = null,
    ) {
        val id
            get() = "$thoughtID/$taskID"

        data class Due(
            val date: Instant,
            val day: Day,
            val showsTime: Boolean,
            val isLate: Boolean,
        ) {
            sealed interface Day {
                data class Past(val days: Int) : Day

                data object Today : Day

                data object Tomorrow : Day

                data object Weekday : Day

                data object Later : Day
            }
        }

        fun due(now: Instant, calendar: ZoneId = ZoneId.systemDefault()): Due? {
            val at = dueAt ?: return null
            val days =
                ChronoUnit.DAYS.between(
                    now.atZone(calendar).toLocalDate(),
                    at.atZone(calendar).toLocalDate(),
                )
            val day =
                when {
                    days < 0 -> Due.Day.Past((-days).toInt())
                    days == 0L -> Due.Day.Today
                    days == 1L -> Due.Day.Tomorrow
                    days in 2L..6L -> Due.Day.Weekday
                    else -> Due.Day.Later
                }
            return Due(at, day, hasTime, days < 0 || days == 0L && hasTime && at <= now)
        }
    }

    data class Counts(val open: Int, val urgent: Int, val doneToday: Int) {
        val focus
            get() = if (urgent > 0) urgent else open

        val progress
            get() =
                if (doneToday + urgent == 0) 0.0 else doneToday.toDouble() / (doneToday + urgent)
    }

    fun sameContent(other: TaskSnapshot?) = other?.copy(generatedAt = generatedAt) == this

    fun counts(at: Instant, calendar: ZoneId = ZoneId.systemDefault()): Counts {
        val end = startOfNextDay(at, calendar)
        return Counts(
            openCount,
            minOf(openCount, dueDates.count { it < end }),
            doneTodayAt.count {
                it.atZone(calendar).toLocalDate() == at.atZone(calendar).toLocalDate()
            },
        )
    }

    fun nextTimed(after: Instant, calendar: ZoneId = ZoneId.systemDefault()) =
        items
            .filter { item ->
                item.hasTime &&
                    item.dueAt?.let {
                        it >= after &&
                            it.atZone(calendar).toLocalDate() ==
                                after.atZone(calendar).toLocalDate()
                    } == true
            }
            .minByOrNull { it.dueAt!! }

    fun completing(
        completion: TaskCompletion,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): TaskSnapshot? {
        val index = items.indexOfFirst {
            it.thoughtID == completion.thoughtID && it.taskID == completion.taskID
        }
        if (index < 0) return null
        val nextItems = items.toMutableList()
        val item = nextItems.removeAt(index)
        val nextDates = dueDates.toMutableList()
        var urgent = urgentCount
        item.dueAt?.let { due ->
            val k = nextDates.indexOfFirst { abs(TaskReminderPlan.secondsBetween(it, due)) < 0.5 }
            if (k >= 0) nextDates.removeAt(k)
            if (due < startOfNextDay(generatedAt, calendar)) urgent = maxOf(0, urgent - 1)
        }
        return copy(
            openCount = maxOf(0, openCount - 1),
            urgentCount = urgent,
            items = nextItems,
            dueDates = nextDates,
            doneTodayAt = (doneTodayAt + completion.at).sorted(),
        )
    }

    fun applying(completions: List<TaskCompletion>, calendar: ZoneId = ZoneId.systemDefault()) =
        completions.fold(this) { snapshot, completion ->
            snapshot.completing(completion, calendar) ?: snapshot
        }

    fun timelineDates(
        from: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
        days: Int = 2,
        limit: Int = 24,
    ): List<Instant> {
        val dates = mutableSetOf(from)
        var midnight = from
        repeat(maxOf(1, days)) {
            midnight = startOfNextDay(midnight, calendar)
            dates.add(midnight)
        }
        for (item in items) if (item.hasTime)
            item.dueAt?.let { if (it > from && it <= midnight) dates.add(it) }
        return dates.sorted().take(maxOf(1, limit))
    }

    companion object {
        const val formatVersion = 1
        const val maxItems = 5
        const val maxDueDates = 500

        fun empty(at: Instant) =
            TaskSnapshot(
                generatedAt = at,
                openCount = 0,
                urgentCount = 0,
                doneTodayAt = emptyList(),
                dueDates = emptyList(),
                items = emptyList(),
            )

        fun startOfNextDay(after: Instant, calendar: ZoneId) =
            after.atZone(calendar).toLocalDate().plusDays(1).atStartOfDay(calendar).toInstant()
    }
}

@Serializable
data class TaskCompletion(
    val thoughtID: String,
    val taskID: String,
    val at: Instant = Instant.now(),
    val id: String = UUID.randomUUID().toString(),
)
