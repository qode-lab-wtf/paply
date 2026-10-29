package com.paply.android.reminders

import com.paply.thoughts.Thought
import com.paply.thoughts.Topic
import com.paply.thoughts.display.TaskReminder
import com.paply.thoughts.display.TaskReminderPlan
import java.time.Instant
import java.time.ZoneId

/** Android policy around the unchanged iOS-derived plan. No Android dependencies: JVM-testable. */
object ReminderPlanning {
    const val WINDOW_LENGTH_MS = 10 * 60 * 1000L
    const val INVITATION_PAUSE_SECONDS = 7 * 24 * 3600L

    data class Access(val beta: Boolean, val enabled: Boolean, val notifications: Boolean, val exact: Boolean) {
        val allowed get() = beta && enabled && notifications
    }

    data class Timing(val exact: Boolean, val startMillis: Long, val windowMillis: Long)

    fun timing(fireAt: Instant, now: Instant, exact: Boolean): Timing {
        if (exact) return Timing(true, fireAt.toEpochMilli(), 0)
        // Android 12+ requires at least ten minutes. Never notify before the requested time.
        val start = maxOf(now.toEpochMilli(), fireAt.toEpochMilli())
        return Timing(false, start, WINDOW_LENGTH_MS)
    }

    fun desired(thoughts: List<Thought>, topicsByThought: Map<String, Topic>, snoozes: Map<String, TaskReminderPlan.Snooze>,
        access: Access, now: Instant, zone: ZoneId, delivered: Map<String, String> = emptyMap()): List<TaskReminder> =
        if (!access.allowed) emptyList() else TaskReminderPlan.reminders(thoughts, { topicsByThought[it.id] }, snoozes, now,
            limit = Int.MAX_VALUE, calendar = zone).filter { delivered[it.id] != it.signature }.take(TaskReminderPlan.limit)

    fun salt(exact: Boolean, zone: ZoneId) = "|android|${if (exact) "exact" else "window"}|${zone.id}"

    fun offersInvitation(taskHasUpcomingTime: Boolean, beta: Boolean, asked: Boolean, hiddenUntil: Instant?, now: Instant) =
        beta && !asked && taskHasUpcomingTime && (hiddenUntil == null || now >= hiddenUntil)

    /** A late broadcast remains valid after startup has removed the elapsed alarm from the pending set. */
    fun stillApplies(reminder: TaskReminder, thoughts: List<Thought>, snoozes: Map<String, TaskReminderPlan.Snooze>, zone: ZoneId): Boolean {
        val thought = thoughts.firstOrNull { it.id == reminder.thoughtID } ?: return false
        val task = thought.tasks.firstOrNull { it.id == reminder.taskID } ?: return false
        val due = TaskReminderPlan.reminderTime(task, thought, zone) ?: return false
        if (kotlin.math.abs(due.toEpochMilli() - reminder.dueAt.toEpochMilli()) >= 1000) return false
        return !reminder.snoozed || snoozes[reminder.id]?.let {
            it.fireAt == reminder.fireAt && kotlin.math.abs(it.dueAt.toEpochMilli() - due.toEpochMilli()) < 1000
        } != false // An elapsed snooze has already been pruned; the journal still identifies its late broadcast.
    }
}

internal data class ReminderUpdate(val data: ReminderData, val schedule: List<TaskReminder>, val cancel: List<String>)

internal fun reconcileReminders(data: ReminderData, thoughts: List<Thought>, topics: Map<String, Topic>,
    access: ReminderPlanning.Access, now: Instant, zone: ZoneId, force: Boolean = false): ReminderUpdate {
    val snoozes = TaskReminderPlan.keptSnoozes(data.snoozes, thoughts = thoughts, now = now, calendar = zone)
    // Delivered entries must not occupy the next-50 slots, even after a clock correction.
    val delivered = data.records.filterValues { it.delivered }.mapValues { it.value.reminder.signature }
    val desired = ReminderPlanning.desired(thoughts, topics, snoozes, access, now, zone, delivered)
    val salt = ReminderPlanning.salt(access.exact, zone)
    val current = data.records.filterValues { it.pending }.mapValues { it.value.stamp }
    val changes = TaskReminderPlan.changes(current, desired, salt)
    val records = data.records.filterValues { ReminderPlanning.stillApplies(it.reminder, thoughts, snoozes, zone) }
        .mapValues { (_, r) -> r.copy(pending = false, deliverable = r.deliverable && access.allowed) }.toMutableMap()
    for (r in desired) records[r.id] = ReminderRecord(r, r.signature + salt)
    return ReminderUpdate(data.copy(records = records, snoozes = snoozes),
        if (force) desired else changes.schedule, changes.remove)
}
