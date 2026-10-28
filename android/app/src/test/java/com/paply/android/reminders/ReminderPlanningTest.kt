package com.paply.android.reminders

import com.paply.thoughts.*
import com.paply.thoughts.display.TaskReminderPlan
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class ReminderPlanningTest {
    private val now = Instant.parse("2026-10-28T14:30:00Z")
    private val due = Instant.parse("2026-10-29T07:00:00Z")
    private val berlin = ZoneId.of("Europe/Berlin")
    private val allowed = ReminderPlanning.Access(beta = true, enabled = true, notifications = true, exact = true)
    private fun task(id: String = "k_1", at: Instant? = due, time: Boolean? = true, hint: String? = null, done: Boolean = false) =
        ThoughtTask(id = id, text = "Briefe bearbeiten", dueAt = at, dueHasTime = time, dueHint = hint, done = done, owner = Owner.ai)
    private fun thought(tasks: List<ThoughtTask> = listOf(task()), deleted: Boolean = false) =
        Thought(id = "s_1", trigger = ThoughtTrigger.app, state = ThoughtState.done, title = "Post", tasks = tasks,
            deletedAt = if (deleted) now else null)
    private fun reconcile(data: ReminderData = ReminderData(enabled = true), thoughts: List<Thought> = listOf(thought()),
        access: ReminderPlanning.Access = allowed, zone: ZoneId = berlin, at: Instant = now, force: Boolean = false) =
        reconcileReminders(data, thoughts, emptyMap(), access, at, zone, force)

    @Test fun selectsOnlyFutureOpenUnambiguousTimedTasks() {
        val tasks = listOf(task("yes"), task("day", time = false), task("unclear", time = null, hint = "irgendwann morgen"),
            task("no-date", at = null), task("done", done = true), task("past", at = now.minusSeconds(1)), task("now", at = now))
        assertEquals(listOf("yes"), reconcile(thoughts = listOf(thought(tasks), thought(deleted = true))).schedule.map { it.taskID })
        assertEquals(due, reconcile().schedule.single().fireAt)
    }

    @Test fun legacySpokenTimeMustMatchStoredTimeInCurrentZone() {
        val t = thought(listOf(task(time = null, hint = "morgen um acht Uhr")))
        assertEquals(1, reconcile(thoughts = listOf(t)).schedule.size)
        assertTrue(reconcile(thoughts = listOf(t), zone = ZoneId.of("America/New_York")).schedule.isEmpty())
    }

    @Test fun repeatsAreIdempotent() {
        val first = reconcile()
        val again = reconcile(first.data, at = now.plusSeconds(60))
        assertTrue(again.schedule.isEmpty()); assertTrue(again.cancel.isEmpty())
        assertEquals(first.data, again.data)
    }

    @Test fun deletedDoneAndTrashedCancelPendingAlarms() {
        val first = reconcile().data
        for (thoughts in listOf(emptyList(), listOf(thought(listOf(task(done = true)))), listOf(thought(deleted = true)))) {
            val next = reconcile(first, thoughts)
            assertEquals(listOf("task/s_1/k_1"), next.cancel); assertTrue(next.schedule.isEmpty()); assertTrue(next.data.records.isEmpty())
        }
    }

    @Test fun timeAndTextEditsReplaceOneAlarmWithSameId() {
        val first = reconcile().data
        val moved = reconcile(first, listOf(thought(listOf(task(at = due.plusSeconds(3600))))))
        assertEquals("task/s_1/k_1", moved.schedule.single().id)
        assertEquals(due.plusSeconds(3600), moved.schedule.single().fireAt)
        val renamed = reconcile(first, listOf(thought(listOf(task().copy(text = "Anderer Text")))))
        assertEquals("Anderer Text", renamed.schedule.single().title)
    }

    @Test fun zoneChangeReschedulesConfirmedInstantWithoutMovingIt() {
        val first = reconcile().data
        val changed = reconcile(first, zone = ZoneId.of("America/New_York"))
        assertEquals(due, changed.schedule.single().fireAt)
        assertNotEquals(first.records.values.single().stamp, changed.data.records.values.single().stamp)
        assertTrue(reconcile(changed.data, zone = ZoneId.of("America/New_York")).schedule.isEmpty())
    }

    @Test fun zoneChangeCancelsUnconfirmedLegacyTime() {
        val t = listOf(thought(listOf(task(time = null, hint = "morgen um acht Uhr"))))
        val first = reconcile(thoughts = t).data
        val changed = reconcile(first, t, zone = ZoneId.of("America/New_York"))
        assertEquals(listOf("task/s_1/k_1"), changed.cancel); assertTrue(changed.schedule.isEmpty())
    }

    @Test fun betaOffCancelsAndOnRestores() {
        val first = reconcile().data
        val off = reconcile(first, access = allowed.copy(beta = false))
        assertEquals(listOf("task/s_1/k_1"), off.cancel); assertTrue(off.schedule.isEmpty())
        assertFalse(off.data.records.values.single().deliverable)
        assertEquals(1, reconcile(off.data).schedule.size)
    }

    @Test fun noPermissionOrSwitchOffPlansNothingAndCancels() {
        for (access in listOf(allowed.copy(notifications = false), allowed.copy(enabled = false))) {
            val update = reconcile(reconcile().data, access = access)
            assertTrue(update.schedule.isEmpty()); assertEquals(listOf("task/s_1/k_1"), update.cancel)
        }
    }

    @Test fun changingExactAccessReplacesAlarmAndKeepsItsIdentity() {
        val first = reconcile().data
        val window = reconcile(first, access = allowed.copy(exact = false))
        assertEquals("task/s_1/k_1", window.schedule.single().id)
        assertTrue(window.data.records.values.single().stamp.contains("|window|"))
        assertEquals(1, reconcile(window.data).schedule.size)
    }

    @Test fun inexactWindowIsCenteredAndCloseTasksNeverStartInThePast() {
        val timing = ReminderPlanning.timing(due, now, exact = false)
        assertEquals(due.toEpochMilli() - 600_000, timing.startMillis)
        assertEquals(1_200_000, timing.windowMillis)
        val near = ReminderPlanning.timing(now.plusSeconds(120), now, exact = false)
        assertEquals(now.toEpochMilli(), near.startMillis); assertEquals(720_000, near.windowMillis)
        assertEquals(0, ReminderPlanning.timing(due, now, exact = true).windowMillis)
    }

    @Test fun rebootForceReRegistersEachDesiredAlarmOnce() {
        val first = reconcile().data
        assertEquals(1, reconcile(first, force = true).schedule.size)
        assertTrue(reconcile(first).schedule.isEmpty())
    }

    @Test fun coldProcessKeepsElapsedRecordForDeliveryButCannotDeliverTwice() {
        val first = reconcile().data
        val elapsed = reconcile(first, at = due.plusSeconds(2))
        val r = elapsed.data.records.values.single()
        assertFalse(r.pending); assertTrue(r.deliverable)
        assertTrue(ReminderPlanning.stillApplies(r.reminder, listOf(thought()), emptyMap(), berlin))
        val delivered = first.copy(records = first.records.mapValues { it.value.copy(pending = false, delivered = true) })
        assertTrue(reconcile(delivered).schedule.isEmpty()) // Even after a backward clock correction.
    }

    @Test fun snoozeSurvivesOffOnAndStopsWhenTaskChanges() {
        val first = reconcile().data
        val id = "task/s_1/k_1"
        val later = due.plusSeconds(3600)
        val snoozed = first.copy(snoozes = mapOf(id to TaskReminderPlan.Snooze(later, due)))
        val off = reconcile(snoozed, access = allowed.copy(beta = false), at = due.plusSeconds(60))
        assertEquals(later, off.data.snoozes[id]?.fireAt)
        val on = reconcile(off.data, at = due.plusSeconds(120))
        assertEquals(later, on.schedule.single().fireAt); assertTrue(on.schedule.single().snoozed)
        assertTrue(reconcile(on.data, listOf(thought(listOf(task(done = true))))).data.snoozes.isEmpty())
    }

    @Test fun invitationRequiresFutureTimeAndLaterLastsSevenDays() {
        assertTrue(ReminderPlanning.offersInvitation(true, true, false, null, now))
        assertFalse(ReminderPlanning.offersInvitation(false, true, false, null, now))
        assertFalse(ReminderPlanning.offersInvitation(true, false, false, null, now))
        assertFalse(ReminderPlanning.offersInvitation(true, true, true, null, now))
        val until = now.plusSeconds(ReminderPlanning.INVITATION_PAUSE_SECONDS)
        assertEquals(604800, until.epochSecond - now.epochSecond)
        assertFalse(ReminderPlanning.offersInvitation(true, true, false, until, until.minusSeconds(1)))
        assertTrue(ReminderPlanning.offersInvitation(true, true, false, until, until))
    }

    @Test fun journalRoundTripKeepsSettingsDeliveryAndSnooze() {
        val first = reconcile().data
        val data = first.copy(asked = true, hiddenUntil = due, records = first.records.mapValues { it.value.copy(delivered = true, pending = false) },
            snoozes = mapOf("task/s_1/k_1" to TaskReminderPlan.Snooze(due.plusSeconds(3600), due)))
        assertEquals(data, ReminderStore.decode(ReminderStore.encode(data)))
    }

    @Test fun earlyWindowDeliveryFillsTheNextSlotWithoutReschedulingDeliveredTasks() {
        val thoughts = listOf(thought((0..50).map { task("k_$it") }))
        val first = reconcile(thoughts = thoughts, access = allowed.copy(exact = false))
        assertEquals(50, first.schedule.size)
        val delivered = first.schedule.first().id
        val afterDelivery = first.data.copy(records = first.data.records.mapValues { (id, r) ->
            if (id == delivered) r.copy(pending = false, delivered = true) else r
        })
        val next = reconcile(afterDelivery, thoughts, access = allowed.copy(exact = false))
        assertEquals(1, next.schedule.size)
        assertTrue(next.schedule.single().id !in first.data.records)
        assertEquals(50, next.data.records.values.count { it.pending })
        assertFalse(next.data.records.getValue(delivered).pending)
    }

    @Test fun partiallyFailedPlatformScheduleRetriesOnlyMissingAlarms() {
        val thoughts = listOf(thought(listOf(task("one"), task("two"))))
        val first = reconcile(thoughts = thoughts).data
        val failed = "task/s_1/two"
        val partial = first.copy(records = first.records.mapValues { (id, r) -> if (id == failed) r.copy(pending = false) else r })
        val retry = reconcile(partial, thoughts)
        assertEquals(listOf(failed), retry.schedule.map { it.id })
        assertTrue(retry.cancel.isEmpty())
        assertTrue(reconcile(retry.data, thoughts).schedule.isEmpty())
    }
}
