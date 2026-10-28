package com.paply.thoughts

import com.paply.thoughts.display.*
import java.time.*
import org.junit.Assert.*
import org.junit.Test

class TaskAgendaTests {
    private val calendar = ZoneId.of("Europe/Berlin")

    private fun date(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0) =
        LocalDateTime.of(y, m, d, h, min).atZone(calendar).toInstant()

    private val now
        get() = date(2026, 10, 27, 15, 30)

    private fun task(
        text: String,
        due: Instant? = null,
        hint: String? = null,
        hasTime: Boolean? = null,
        done: Boolean = false,
        doneAt: Instant? = null,
    ) =
        ThoughtTask(
            id = "k_$text",
            text = text,
            dueHint = hint,
            dueAt = due,
            dueHasTime = hasTime,
            done = done,
            doneAt = doneAt,
            owner = Owner.ai,
        )

    private fun thought(
        id: String,
        created: Instant = now,
        tasks: List<ThoughtTask>,
        deleted: Instant? = null,
    ) =
        Thought(
            id = id,
            createdAt = created,
            trigger = ThoughtTrigger.app,
            state = ThoughtState.done,
            title = id,
            tasks = tasks,
            deletedAt = deleted,
        )

    @Test
    fun everyOpenTaskAppearsExactlyOnce() {
        val expected = mutableSetOf<String>()
        val thoughts =
            (0..<120).map { i ->
                val tasks =
                    (0..<i % 7).map { k ->
                        val due =
                            when ((i + k) % 4) {
                                0 -> null
                                1 -> now.minusSeconds((k + 1) * 86400L)
                                2 -> now.plusSeconds(k * 3600L - 7200)
                                else -> now.plusSeconds((k + 1) * 86400L)
                            }
                        val done = (i + k) % 9 == 0
                        if (!done) expected.add("k_$i-$k")
                        task(
                            "$i-$k",
                            due,
                            done = done,
                            doneAt = if (done) now.minusSeconds(i * 3600L) else null,
                        )
                    }
                thought("s_$i", now.minusSeconds(i * 50000L), tasks)
            }
        val agenda = TaskAgenda(thoughts, now, calendar)
        val shown = TaskAgenda.Group.entries.flatMap { agenda.items(it).map { x -> x.task.id } }
        assertEquals(expected.size, shown.size)
        assertEquals(expected, shown.toSet())
        assertEquals(expected.size, agenda.openCount)
        assertTrue(agenda.allDone.none { it.task.id in expected })
    }

    @Test
    fun sameTaskIDInTwoThoughtsStaysTwoRows() {
        val shared = task("gleich", now)
        val agenda =
            TaskAgenda(
                listOf(
                    thought("s_1", tasks = listOf(shared)),
                    thought("s_2", tasks = listOf(shared)),
                ),
                now,
                calendar,
            )
        assertEquals(2, agenda.today.size)
        assertEquals(2, agenda.today.map { it.id }.toSet().size)
    }

    @Test
    fun groupsFollowTheCalendarDay() {
        val tasks =
            listOf(
                task("gestern spät", date(2026, 10, 26, 23, 59)),
                task("heute früh", date(2026, 10, 27, 0, 0)),
                task("heute abend", date(2026, 10, 27, 23, 59)),
                task("morgen", date(2026, 10, 28, 0, 0)),
                task("ohne"),
            )
        val thoughts = listOf(thought("s_a", tasks = tasks))
        val agenda = TaskAgenda(thoughts, now, calendar)
        assertEquals(listOf("gestern spät"), agenda.overdue.map { it.task.text })
        assertEquals(listOf("heute früh", "heute abend"), agenda.today.map { it.task.text })
        assertEquals(listOf("morgen"), agenda.upcoming.map { it.task.text })
        assertEquals(listOf("ohne"), agenda.someday.map { it.task.text })
        assertEquals(3, agenda.urgentCount)
        assertEquals(3, TaskAgenda.urgentCount(thoughts, now, calendar))
        assertEquals(
            TaskAgenda.Group.upcoming,
            TaskAgenda.group(date(2026, 10, 28, 0, 0), now, calendar),
        )
        assertEquals(TaskAgenda.Group.someday, TaskAgenda.group(null, now, calendar))
    }

    @Test
    fun deletedThoughtsAndDoneTasksAreNotOpen() {
        val thoughts =
            listOf(
                thought("s_trash", tasks = listOf(task("weg", now)), deleted = now),
                thought(
                    "s_live",
                    tasks =
                        listOf(task("offen", now), task("fertig", now, done = true, doneAt = now)),
                ),
            )
        val agenda = TaskAgenda(thoughts, now, calendar)
        assertEquals(listOf("offen"), agenda.today.map { it.task.text })
        assertEquals(listOf("fertig"), agenda.allDone.map { it.task.text })
        assertEquals(1, agenda.urgentCount)
        assertEquals(1, TaskAgenda.urgentCount(thoughts, now, calendar))
    }

    @Test
    fun orderIsByDateThenStable() {
        val early = date(2026, 10, 30, 9)
        val a = thought("s_new", tasks = listOf(task("b2", early), task("x1"), task("x2")))
        val b =
            thought(
                "s_old",
                now.minusSeconds(86400),
                listOf(task("b1", early), task("a", date(2026, 10, 29)), task("y")),
            )
        val agenda = TaskAgenda(listOf(a, b), now, calendar)
        assertEquals(listOf("a", "b2", "b1"), agenda.upcoming.map { it.task.text })
        assertEquals(listOf("x1", "x2", "y"), agenda.someday.map { it.task.text })
    }

    @Test
    fun doneWindowIsSevenCalendarDays() {
        val tasks =
            listOf(
                task("heute", done = true, doneAt = date(2026, 10, 27, 8)),
                task("vor 6 Tagen", done = true, doneAt = date(2026, 10, 21, 0, 1)),
                task("vor 7 Tagen", done = true, doneAt = date(2026, 10, 20, 23, 59)),
                task("ohne Zeitpunkt", done = true),
            )
        val agenda = TaskAgenda(listOf(thought("s_d", tasks = tasks)), now, calendar)
        assertEquals(listOf("heute", "vor 6 Tagen"), agenda.recentlyDone.map { it.task.text })
        assertEquals(tasks.map { it.text }, agenda.allDone.map { it.task.text })
    }

    private fun label(t: ThoughtTask, recorded: Instant) =
        TaskDueLabel.make(t, recorded, now, calendar)

    @Test
    fun wordingStaysOnTheDayOfRecording() {
        assertEquals(
            TaskDueLabel.Wording("morgen"),
            label(task("Arzt", date(2026, 10, 28), "morgen"), date(2026, 10, 27, 9)),
        )
    }

    @Test
    fun staleWordingBecomesTheDay() {
        assertEquals(
            TaskDueLabel.Today(null),
            label(task("Arzt", date(2026, 10, 27), "morgen"), date(2026, 10, 26, 9)),
        )
        assertEquals(
            TaskDueLabel.Tomorrow(null),
            label(task("Bank", date(2026, 10, 28), "übermorgen"), date(2026, 10, 26)),
        )
        assertEquals(
            TaskDueLabel.Yesterday(null),
            label(task("Miete", date(2026, 10, 26), "morgen"), date(2026, 10, 25)),
        )
        assertEquals(
            TaskDueLabel.Weekday(date(2026, 10, 30), null),
            label(task("Flug", date(2026, 10, 30), "Freitag"), date(2026, 10, 25)),
        )
        assertEquals(
            TaskDueLabel.Date(date(2026, 11, 10), null),
            label(task("Steuer", date(2026, 11, 10), "am 10. November"), date(2026, 10, 20)),
        )
    }

    @Test
    fun timeOnlyWhenSpoken() {
        assertEquals(
            TaskDueLabel.Today(date(2026, 10, 27, 15)),
            label(task("Anruf", date(2026, 10, 27, 15), "morgen um 15 Uhr"), date(2026, 10, 26)),
        )
        assertEquals(
            TaskDueLabel.Today(null),
            label(task("Post", date(2026, 10, 27), "am 27."), date(2026, 10, 20)),
        )
    }

    @Test
    fun withoutDateOnlyTheWording() {
        assertEquals(
            TaskDueLabel.Wording("bald"),
            label(task("a", hint = "bald"), date(2026, 10, 1)),
        )
        assertNull(label(task("b", hint = "  "), now))
        assertNull(label(task("c"), now))
    }

    @Test
    fun spokenTimeIsKeptByTheResolver() {
        for ((hint, hour, minute) in
            listOf(
                Triple("morgen um 12 Uhr", 12, 0),
                Triple("morgen um 0 Uhr", 0, 0),
                Triple("morgen um acht Uhr", 8, 0),
                Triple("morgen um halb drei", 14, 30),
            )) {
            val due = date(2026, 10, 27, hour, minute)
            assertEquals(
                TaskDueLabel.Today(due),
                label(task(hint, due, hint, true), date(2026, 10, 26, 9)),
            )
        }
        for ((hint, hour) in
            listOf("morgen" to 12, "morgen früh" to 9, "morgen um 15 Uhr" to 15)) assertEquals(
            TaskDueLabel.Today(null),
            label(task(hint, date(2026, 10, 27, hour), hint, false), date(2026, 10, 26, 9)),
        )
    }

    @Test
    fun olderTasksDecideByTheWording() {
        data class Row(val hint: String, val hour: Int, val minute: Int, val shown: Boolean)
        val rows =
            listOf(
                Row("morgen um 12 Uhr", 12, 0, true),
                Row("morgen um 0 Uhr", 0, 0, true),
                Row("morgen um null Uhr", 0, 0, true),
                Row("morgen um acht Uhr", 8, 0, true),
                Row("morgen um halb drei", 14, 30, true),
                Row("morgen um Viertel nach acht", 8, 15, true),
                Row("morgen um 07:00", 7, 0, true),
                Row("morgen um 7 Uhr früh", 7, 0, true),
                Row("tomorrow at 8", 8, 0, true),
                Row("tomorrow 8 pm", 20, 0, true),
                Row("morgen um acht Uhr", 12, 0, false),
                Row("morgen um 7 Uhr früh", 19, 0, false),
                Row("morgen um 07:00", 19, 0, false),
                Row("tomorrow at half past eight pm", 8, 30, false),
                Row("tomorrow at eight", 12, 0, false),
                Row("morgen", 12, 0, false),
                Row("morgen früh", 9, 0, false),
                Row("morgen Mittag", 12, 0, false),
                Row("am 27.", 12, 0, false),
            )
        for (r in rows) {
            val due = date(2026, 10, 27, r.hour, r.minute)
            assertEquals(
                r.hint,
                TaskDueLabel.Today(if (r.shown) due else null),
                label(task("alt", due, r.hint), date(2026, 10, 26, 9)),
            )
        }
    }

    @Test
    fun midnightIsTheStartOfTheNextDay() {
        val due = date(2026, 10, 28, 0)
        assertEquals(
            TaskDueLabel.Tomorrow(due),
            label(task("Abgabe", due, "morgen um Mitternacht"), date(2026, 10, 26, 9)),
        )
    }
}
