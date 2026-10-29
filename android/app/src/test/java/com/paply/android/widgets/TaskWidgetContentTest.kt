package com.paply.android.widgets

import com.paply.thoughts.*
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class TaskWidgetContentTest {
    private val now = Instant.parse("2026-10-29T10:00:00Z")
    private val zone = ZoneId.of("Europe/Berlin")
    private fun task(id: String, due: Instant? = null, done: Boolean = false) =
        ThoughtTask(id = id, text = id, dueAt = due, done = done, owner = Owner.user)
    private fun thought(id: String, vararg tasks: ThoughtTask) =
        Thought(id = id, trigger = ThoughtTrigger.app, state = ThoughtState.done, tasks = tasks.toList())
    private fun content(thoughts: List<Thought>, beta: Boolean = true, locked: Boolean = false, at: Instant = now) =
        TaskWidgetContent.make(thoughts, beta = beta, keyguard = locked, now = at, zone = zone)

    @Test fun selectsOpenTasksInAgendaOrderAndKeepsTotalBeyondThree() {
        val source = thought("s", task("someday"), task("later", now.plusSeconds(86400)),
            task("today", now.plusSeconds(3600)), task("overdue", now.minusSeconds(86400)), task("done", done = true))
        val result = content(listOf(source))
        assertEquals(4, result.openCount)
        assertEquals(listOf("overdue"), result.items(false).map { it.taskID })
        assertEquals(listOf("overdue", "today", "later"), result.items(true).map { it.taskID })
    }
    @Test fun equalDueDatesKeepSourceOrder() {
        val result = content(listOf(thought("a", task("one", now), task("two", now)), thought("b", task("three", now))))
        assertEquals(listOf("one", "two", "three"), result.items(true).map { it.taskID })
    }
    @Test fun excludesTrashEmptyAndRecording() {
        val source = thought("s", task("visible"))
        val result = content(listOf(source, thought("trash", task("private")).copy(deletedAt = now),
            thought("empty", task("empty")).copy(state = ThoughtState.empty),
            thought("recording", task("recording")).copy(state = ThoughtState.recording)))
        assertEquals(1, result.openCount)
        assertEquals("visible", result.items(false).single().text)
    }
    @Test fun emptyAndAllDoneAreQuiet() {
        for (thoughts in listOf(emptyList(), listOf(thought("s", task("done", done = true))))) {
            val result = content(thoughts)
            assertEquals(0, result.openCount)
            assertEquals("Alles erledigt", result.note)
            assertTrue(result.items(true).isEmpty())
        }
    }
    @Test fun betaOffHidesTextCountsAndActionsEvenWithData() {
        val result = content(listOf(thought("s", task("secret"))), beta = false)
        assertNull(result.snapshot); assertNull(result.openCount)
        assertTrue(result.items(true).isEmpty()); assertEquals(TaskWidgetContent.BETA_OFF, result.note)
    }
    @Test fun keyguardNeverContainsTasksOrCount() {
        val result = content(listOf(thought("s", task("secret"))), locked = true)
        assertNull(result.snapshot); assertNull(result.openCount)
        assertTrue(result.items(true).isEmpty()); assertEquals(TaskWidgetContent.LOCKED, result.note)
    }
    @Test fun noDataDoesNotPretendEverythingIsDone() {
        val result = TaskWidgetContent.make(emptyList(), beta = true, loaded = false, now = now)
        assertNull(result.snapshot); assertTrue(result.note!!.contains("Öffne Paply"))
    }
    @Test fun dueLabelsChangeAtLocalMidnight() {
        val at = Instant.parse("2026-10-29T22:59:00Z")
        val entry = content(listOf(thought("s", task("next", at.plusSeconds(120)))), at = at).items(false).single()
        assertEquals("Morgen", TaskWidgetContent.due(entry, at, zone))
        assertEquals("Heute", TaskWidgetContent.due(entry, at.plusSeconds(61), zone))
    }
}
