package com.paply.thoughts

import com.paply.thoughts.display.*
import com.paply.thoughts.model.ThoughtJSON
import java.time.*
import org.junit.Assert.*
import org.junit.Test

class TaskReminderPlanTests {
    private val calendar = ZoneId.of("Europe/Berlin")

    private fun date(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0) =
        LocalDateTime.of(y, m, d, h, min).atZone(calendar).toInstant()

    private val now
        get() = date(2026, 10, 28, 15, 30)

    private fun task(
        id: String,
        due: Instant? = null,
        hint: String? = null,
        hasTime: Boolean? = true,
        done: Boolean = false,
        text: String? = null,
    ) =
        ThoughtTask(
            id = id,
            text = text ?: "Aufgabe $id",
            dueHint = hint,
            dueAt = due,
            dueHasTime = hasTime,
            done = done,
            doneAt = if (done) now else null,
            owner = Owner.ai,
        )

    private fun thought(
        id: String,
        title: String? = "Post von Aram",
        topic: String? = "t_arbeit",
        tasks: List<ThoughtTask>,
        deleted: Instant? = null,
    ) =
        Thought(
            id = id,
            createdAt = date(2026, 10, 27, 9),
            trigger = ThoughtTrigger.app,
            state = ThoughtState.done,
            title = title,
            topicId = topic,
            tasks = tasks,
            deletedAt = deleted,
        )

    private val topics =
        mapOf("t_arbeit" to Topic("t_arbeit", "Arbeit", TopicIcon.briefcase, Owner.ai))

    private fun plan(
        thoughts: List<Thought>,
        snoozes: Map<String, TaskReminderPlan.Snooze> = emptyMap(),
        now: Instant = this.now,
        limit: Int = 50,
    ) = TaskReminderPlan.reminders(thoughts, { topics[it.topicId] }, snoozes, now, limit, calendar)

    private fun stamps(reminders: List<TaskReminder>, salt: String = "") = reminders.associate {
        it.id to it.signature + salt
    }

    @Test
    fun onlyOpenFutureTasksWithSpokenTime() {
        val due = date(2026, 10, 29, 8)
        val tasks =
            listOf(
                task("k_ja", due),
                task("k_nurTag", date(2026, 10, 29), hasTime = false),
                task("k_ohneDatum", hasTime = null),
                task("k_erledigt", due, done = true),
                task("k_vorbei", date(2026, 10, 28, 15)),
                task("k_genauJetzt", now),
            )
        val reminders =
            plan(
                listOf(
                    thought("s_1", tasks = tasks),
                    thought("s_weg", tasks = listOf(task("k_papierkorb", due)), deleted = now),
                ),
            )
        assertEquals(listOf("k_ja"), reminders.map { it.taskID })
        assertEquals(due, reminders.single().fireAt)
        assertEquals(due, reminders.single().dueAt)
        assertFalse(reminders.single().snoozed)
    }

    @Test
    fun olderTasksFollowTheListRule() {
        val tasks =
            listOf(
                task("k_acht", date(2026, 10, 29, 8), "morgen um acht Uhr", null),
                task("k_falsch", date(2026, 10, 29), "morgen um acht Uhr", null),
                task("k_morgen", date(2026, 10, 29), "morgen", null),
            )
        assertEquals(
            listOf("k_acht"),
            plan(listOf(thought("s_1", tasks = tasks))).map { it.taskID },
        )
        tasks.forEach { t ->
            val shown = TaskDueLabel.make(t, date(2026, 10, 20), now, calendar)
            assertEquals(t.id == "k_acht", (shown as? TaskDueLabel.Tomorrow)?.time != null)
        }
    }

    @Test
    fun contentIsTaskTopicAndThought() {
        val due = date(2026, 10, 29, 8)
        val byTask =
            plan(
                    listOf(
                        thought(
                            "s_1",
                            tasks =
                                listOf(task("k_1", due, text = "  Briefe bei Aram bearbeiten ")),
                        ),
                        thought("s_2", title = null, tasks = listOf(task("k_2", due))),
                        thought("s_3", topic = null, tasks = listOf(task("k_3", due))),
                        thought(
                            "s_4",
                            title = "  ",
                            topic = null,
                            tasks = listOf(task("k_4", due)),
                        ),
                    ),
                )
                .associateBy { it.taskID }
        assertEquals("Briefe bei Aram bearbeiten", byTask["k_1"]?.title)
        assertEquals("Arbeit · Post von Aram", byTask["k_1"]?.body)
        assertEquals("paply.topic.t_arbeit", byTask["k_1"]?.threadID)
        assertEquals("Arbeit", byTask["k_2"]?.body)
        assertEquals("Post von Aram", byTask["k_3"]?.body)
        assertEquals("paply.topic.none", byTask["k_3"]?.threadID)
        assertEquals("", byTask["k_4"]?.body)
    }

    @Test
    fun upcomingCardNeedsAFutureTimedOpenTask() {
        fun upcoming(t: ThoughtTask) =
            TaskReminderPlan.hasUpcoming(listOf(thought("s_1", tasks = listOf(t))), now, calendar)
        assertTrue(upcoming(task("k_1", date(2026, 10, 29, 8))))
        assertFalse(upcoming(task("k_1", date(2026, 10, 28, 8))))
        assertFalse(upcoming(task("k_1", date(2026, 10, 29, 8), hasTime = false)))
        assertFalse(upcoming(task("k_1", date(2026, 10, 29, 8), done = true)))
        assertFalse(TaskReminderPlan.hasUpcoming(emptyList(), now, calendar))
    }

    @Test
    fun identifiersAreStableAndReadable() {
        val id = TaskReminderPlan.identifier("s_abc", "k_def")
        assertEquals("task/s_abc/k_def", id)
        assertEquals(TaskKey("s_abc", "k_def"), TaskReminderPlan.parse(id))
        listOf("task/s_abc", "task//k", "andere/s/k").forEach {
            assertNull(TaskReminderPlan.parse(it))
        }
        val thoughts = listOf(thought("s_1", tasks = listOf(task("k_1", date(2026, 10, 29, 8)))))
        assertEquals(plan(thoughts), plan(thoughts, now = now.plusSeconds(600)))
        assertEquals(listOf("task/s_1/k_1"), plan(thoughts).map { it.id })
        assertEquals(
            2,
            plan(
                    listOf(
                        thought("s_1", tasks = listOf(task("k_x", date(2026, 10, 29, 8)))),
                        thought("s_2", tasks = listOf(task("k_x", date(2026, 10, 29, 8)))),
                    ),
                )
                .map { it.id }
                .toSet()
                .size,
        )
    }

    @Test
    fun reconcileAddsChangesAndRemoves() {
        val due = date(2026, 10, 29, 8)
        val old =
            plan(
                listOf(
                    thought(
                        "s_1",
                        tasks =
                            listOf("k_bleibt", "k_zeit", "k_text", "k_weg").map { task(it, due) },
                    ),
                ),
            )
        val new =
            plan(
                listOf(
                    thought(
                        "s_1",
                        tasks =
                            listOf(
                                task("k_bleibt", due),
                                task("k_zeit", date(2026, 10, 29, 9)),
                                task("k_text", due, text = "Neuer Text"),
                                task("k_neu", due),
                            ),
                    ),
                ),
            )
        val changes = TaskReminderPlan.changes(stamps(old), new)
        assertEquals(setOf("k_zeit", "k_text", "k_neu"), changes.schedule.map { it.taskID }.toSet())
        assertEquals(listOf("task/s_1/k_weg"), changes.remove)
        assertEquals(1, changes.unchanged)
        val again = TaskReminderPlan.changes(stamps(new), new)
        assertTrue(again.isEmpty)
        assertEquals(new.size, again.unchanged)
        val salted = TaskReminderPlan.changes(stamps(new), new, "|dringlich")
        assertEquals(new.size, salted.schedule.size)
        assertTrue(salted.remove.isEmpty())
        assertTrue(TaskReminderPlan.changes(stamps(new, "|dringlich"), new, "|dringlich").isEmpty)
    }

    @Test
    fun doneDeletedOrTrashedRemovesPlanned() {
        val due = date(2026, 10, 29, 8)
        val before =
            plan(
                listOf(
                    thought("s_1", tasks = listOf(task("k_1", due), task("k_2", due))),
                    thought("s_2", tasks = listOf(task("k_3", due))),
                ),
            )
        val after =
            plan(
                listOf(
                    thought("s_1", tasks = listOf(task("k_1", due, done = true))),
                    thought("s_2", tasks = listOf(task("k_3", due)), deleted = now),
                ),
            )
        val changes = TaskReminderPlan.changes(stamps(before), after)
        assertTrue(changes.schedule.isEmpty())
        assertEquals(listOf("task/s_1/k_1", "task/s_1/k_2", "task/s_2/k_3"), changes.remove)
        assertEquals(
            listOf("task/s_2/k_3"),
            TaskReminderPlan.changes(
                    emptyMap(),
                    plan(listOf(thought("s_2", tasks = listOf(task("k_3", due))))),
                )
                .schedule
                .map { it.id },
        )
    }

    @Test
    fun deliveredOfDoneOrDeletedTasksAreStale() {
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks =
                        listOf(
                            task("k_offen", date(2026, 10, 28, 8)),
                            task("k_erledigt", date(2026, 10, 28, 8), done = true),
                        ),
                ),
                thought(
                    "s_2",
                    tasks = listOf(task("k_papierkorb", date(2026, 10, 28, 8))),
                    deleted = now,
                ),
            )
        val delivered =
            listOf(
                "task/s_1/k_offen",
                "task/s_1/k_erledigt",
                "task/s_1/k_geloescht",
                "task/s_2/k_papierkorb",
                "task/s_weg/k_1",
                "fremd",
            )
        assertEquals(delivered.subList(1, 5), TaskReminderPlan.stale(delivered, thoughts))
    }

    @Test
    fun snoozeOnlyForOpenTasks() {
        val due = date(2026, 10, 28, 16)
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks = listOf(task("k_offen", due), task("k_erledigt", due, done = true)),
                ),
                thought("s_weg", tasks = listOf(task("k_papierkorb", due)), deleted = now),
            )
        fun may(
            t: String,
            k: String,
            loaded: List<Thought>? = thoughts,
            queued: Boolean = false,
            snapshot: Boolean? = null,
            locked: Boolean = false,
        ) =
            TaskReminderPlan.maySnooze(
                t,
                k,
                TaskReminderPlan.SnoozeFacts(loaded, queued, snapshot, locked),
            )
        assertTrue(may("s_1", "k_offen"))
        assertFalse(may("s_1", "k_erledigt"))
        assertFalse(may("s_1", "k_geloescht"))
        assertFalse(may("s_weg", "k_papierkorb"))
        assertFalse(may("s_fehlt", "k_1"))
        assertFalse(may("s_1", "k_offen", queued = true))
        assertFalse(may("s_1", "k_offen", null, true, locked = true))
        assertTrue(may("s_1", "k_offen", null, snapshot = true))
        assertFalse(may("s_1", "k_offen", null, snapshot = false))
        assertFalse(may("s_1", "k_offen", null))
        assertTrue(may("s_1", "k_offen", null, locked = true))
    }

    @Test
    fun betaOffRemovesEveryDeliveredReminderButNothingElse() {
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks =
                        listOf(
                            task("k_offen", date(2026, 10, 28, 8)),
                            task("k_erledigt", date(2026, 10, 28, 8), done = true),
                        ),
                ),
            )
        val delivered =
            listOf(
                "task/s_1/k_offen",
                "task/s_1/k_erledigt",
                "task/s_weg/k_1",
                "test/s_x",
                "fremd",
                "task/kaputt",
            )
        assertEquals(
            delivered.take(3),
            TaskReminderPlan.removableDelivered(delivered, thoughts, false),
        )
        assertEquals(
            TaskReminderPlan.stale(delivered, thoughts),
            TaskReminderPlan.removableDelivered(delivered, thoughts, true),
        )
        assertEquals(
            delivered.subList(1, 3),
            TaskReminderPlan.removableDelivered(delivered, thoughts, true),
        )
    }

    @Test
    fun betaOffPlansNothingAndOnRestoresAll() {
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks =
                        listOf(
                            task("k_1", date(2026, 10, 29, 8)),
                            task("k_2", date(2026, 10, 30, 9)),
                        ),
                ),
            )
        val planned = plan(thoughts)
        assertEquals(2, planned.size)
        val off = TaskReminderPlan.changes(stamps(planned, "|normal"), emptyList(), "|normal")
        assertTrue(off.schedule.isEmpty())
        assertEquals(listOf("task/s_1/k_1", "task/s_1/k_2"), off.remove)
        val on = TaskReminderPlan.changes(emptyMap(), plan(thoughts), "|normal")
        assertEquals(planned, on.schedule)
        assertTrue(on.remove.isEmpty())
    }

    @Test
    fun plansOnlyTheNextFiftyByTime() {
        val thoughts =
            (0..<8).map { i ->
                thought(
                    "s_$i",
                    tasks =
                        (0..<10).map { k ->
                            task(
                                "k_${i}_$k",
                                now.plusSeconds((((i * 10 + k) * 37) % 80 + 1) * 3600L),
                            )
                        },
                )
            }
        val reminders = plan(thoughts)
        assertEquals(50, reminders.size)
        assertEquals(reminders.map { it.fireAt }.sorted(), reminders.map { it.fireAt })
        assertEquals(now.plusSeconds(3600), reminders.first().fireAt)
        assertEquals(now.plusSeconds(50 * 3600), reminders.last().fireAt)
        val earliest = reminders.first()
        val fewer = thoughts.map { t ->
            if (t.id == earliest.thoughtID)
                t.copy(
                    tasks =
                        t.tasks.map { if (it.id == earliest.taskID) it.copy(done = true) else it },
                )
            else t
        }
        val next = plan(fewer)
        assertEquals(50, next.size)
        assertEquals(now.plusSeconds(51 * 3600), next.last().fireAt)
        val changes = TaskReminderPlan.changes(stamps(reminders), next)
        assertEquals(listOf(earliest.id), changes.remove)
        assertEquals(1, changes.schedule.size)
        assertEquals(49, changes.unchanged)
    }

    @Test
    fun limitIsConfigurable() {
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks = (0..<5).map { task("k_$it", now.plusSeconds((it + 1) * 60L)) },
                ),
            )
        assertEquals(listOf("k_0", "k_1", "k_2"), plan(thoughts, limit = 3).map { it.taskID })
        assertTrue(plan(thoughts, limit = 0).isEmpty())
    }

    @Test
    fun snoozeMovesTheReminderByOneHour() {
        val fired = date(2026, 10, 28, 15)
        val later = TaskReminderPlan.snoozed(date(2026, 10, 28, 15, 2).plusMillis(700))
        assertEquals(date(2026, 10, 28, 16, 2), later)
        val thoughts = listOf(thought("s_1", tasks = listOf(task("k_1", fired))))
        val snoozes = mapOf("task/s_1/k_1" to TaskReminderPlan.Snooze(later, fired))
        assertTrue(plan(thoughts).isEmpty())
        val reminder = plan(thoughts, snoozes).single()
        assertEquals(later, reminder.fireAt)
        assertEquals(fired, reminder.dueAt)
        assertTrue(reminder.snoozed)
        assertTrue(plan(thoughts, snoozes, later.plusSeconds(1)).isEmpty())
    }

    @Test
    fun snoozeEndsWhenTheTaskChanges() {
        val fired = date(2026, 10, 28, 15)
        val later = date(2026, 10, 28, 16, 2)
        val snoozes = mapOf("task/s_1/k_1" to TaskReminderPlan.Snooze(later, fired))
        assertTrue(
            plan(listOf(thought("s_1", tasks = listOf(task("k_1", fired, done = true)))), snoozes)
                .isEmpty(),
        )
        assertTrue(
            plan(listOf(thought("s_1", tasks = listOf(task("k_1", fired)), deleted = now)), snoozes)
                .isEmpty(),
        )
        val newDue = date(2026, 10, 30, 9)
        val moved =
            plan(listOf(thought("s_1", tasks = listOf(task("k_1", newDue)))), snoozes).single()
        assertEquals(newDue, moved.fireAt)
        assertFalse(moved.snoozed)
        assertEquals(
            later,
            plan(
                    listOf(thought("s_1", tasks = listOf(task("k_1", fired.plusMillis(400))))),
                    snoozes,
                )
                .single()
                .fireAt,
        )
    }

    @Test
    fun snoozedReminderIsRescheduledOnlyOnce() {
        val fired = date(2026, 10, 28, 15)
        val later = date(2026, 10, 28, 16, 2)
        val id = "task/s_1/k_1"
        val desired =
            plan(
                listOf(thought("s_1", tasks = listOf(task("k_1", fired)))),
                mapOf(id to TaskReminderPlan.Snooze(later, fired)),
            )
        assertTrue(TaskReminderPlan.changes(stamps(desired), desired).isEmpty)
        assertNotEquals(
            desired.single().signature,
            desired.single().copy(snoozed = false).signature,
        )
    }

    @Test
    fun snoozeSurvivesTurningOffAndOn() {
        val fired = date(2026, 10, 28, 15)
        val later = date(2026, 10, 28, 16, 2)
        val id = "task/s_1/k_1"
        val snooze = TaskReminderPlan.Snooze(later, fired)
        val thoughts = listOf(thought("s_1", tasks = listOf(task("k_1", fired))))
        var stored =
            TaskReminderPlan.keptSnoozes(emptyMap(), mapOf(id to snooze), thoughts, now, calendar)
        assertEquals(mapOf(id to snooze), stored)
        assertEquals(
            listOf(id),
            TaskReminderPlan.changes(stamps(plan(thoughts, stored)), emptyList()).remove,
        )
        stored =
            TaskReminderPlan.keptSnoozes(
                stored,
                thoughts = null,
                now = now.plusSeconds(60),
                calendar = calendar,
            )
        stored =
            TaskReminderPlan.keptSnoozes(
                stored,
                thoughts = thoughts,
                now = now.plusSeconds(120),
                calendar = calendar,
            )
        assertEquals(mapOf(id to snooze), stored)
        val back = plan(thoughts, stored, now.plusSeconds(180)).single()
        assertEquals(later, back.fireAt)
        assertTrue(back.snoozed)
        assertEquals(
            stored,
            ThoughtJSON.decode<Map<String, TaskReminderPlan.Snooze>>(ThoughtJSON.encode(stored)),
        )
    }

    @Test
    fun expiredSnoozeIsCleanedUp() {
        val fired = date(2026, 10, 28, 15)
        val later = date(2026, 10, 28, 16, 2)
        val id = "task/s_1/k_1"
        val snooze = TaskReminderPlan.Snooze(later, fired)
        val stored = mapOf(id to snooze, "fremd" to snooze)
        val thoughts = listOf(thought("s_1", tasks = listOf(task("k_1", fired))))
        assertEquals(
            setOf(id),
            TaskReminderPlan.keptSnoozes(
                    stored,
                    thoughts = thoughts,
                    now = now,
                    calendar = calendar,
                )
                .keys,
        )
        for (loaded in listOf(thoughts, null)) assertTrue(
            TaskReminderPlan.keptSnoozes(
                    stored,
                    thoughts = loaded,
                    now = later.plusSeconds(1),
                    calendar = calendar,
                )
                .isEmpty(),
        )
        assertTrue(
            TaskReminderPlan.keptSnoozes(stored, thoughts = null, now = later, calendar = calendar)
                .isEmpty(),
        )
        assertTrue(
            TaskReminderPlan.keptSnoozes(
                    stored,
                    thoughts =
                        listOf(thought("s_1", tasks = listOf(task("k_1", date(2026, 10, 30, 9))))),
                    now = now,
                    calendar = calendar,
                )
                .isEmpty(),
        )
    }

    @Test
    fun snoozeOfDoneOrDeletedTaskIsNotPlanned() {
        val fired = date(2026, 10, 28, 15)
        val later = date(2026, 10, 28, 16, 2)
        val snooze = TaskReminderPlan.Snooze(later, fired)
        val ids =
            listOf(
                "task/s_1/k_erledigt",
                "task/s_1/k_geloescht",
                "task/s_weg/k_1",
                "task/s_fehlt/k_1",
                "task/s_1/k_offen",
            )
        val stored = ids.associateWith { snooze }
        val thoughts =
            listOf(
                thought(
                    "s_1",
                    tasks = listOf(task("k_erledigt", fired, done = true), task("k_offen", fired)),
                ),
                thought("s_weg", tasks = listOf(task("k_1", fired)), deleted = now),
            )
        assertEquals(
            setOf("task/s_1/k_offen"),
            TaskReminderPlan.keptSnoozes(
                    stored,
                    thoughts = thoughts,
                    now = now,
                    calendar = calendar,
                )
                .keys,
        )
        assertEquals(listOf("task/s_1/k_offen"), plan(thoughts, stored).map { it.id })
        assertEquals(
            stored,
            TaskReminderPlan.keptSnoozes(stored, thoughts = null, now = now, calendar = calendar),
        )
    }

    @Test
    fun laterSnoozeWinsWhenStoredAndPlannedDiffer() {
        val fired = date(2026, 10, 28, 15)
        val id = "task/s_1/k_1"
        val thoughts = listOf(thought("s_1", tasks = listOf(task("k_1", fired))))
        val first = TaskReminderPlan.Snooze(date(2026, 10, 28, 16, 2), fired)
        val second = TaskReminderPlan.Snooze(date(2026, 10, 28, 17, 5), fired)
        assertEquals(
            mapOf(id to second),
            TaskReminderPlan.keptSnoozes(
                mapOf(id to first),
                mapOf(id to second),
                thoughts,
                now,
                calendar,
            ),
        )
        assertEquals(
            mapOf(id to second),
            TaskReminderPlan.keptSnoozes(
                mapOf(id to second),
                mapOf(id to first),
                thoughts,
                now,
                calendar,
            ),
        )
    }
}
