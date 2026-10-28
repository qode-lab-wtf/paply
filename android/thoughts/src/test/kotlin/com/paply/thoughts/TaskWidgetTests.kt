package com.paply.thoughts

import com.paply.thoughts.display.*
import com.paply.thoughts.model.ThoughtJSON
import java.time.*
import org.junit.Assert.*
import org.junit.Test

class TaskWidgetTests {
    private val calendar = ZoneId.of("Europe/Berlin")

    private fun date(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0) =
        LocalDateTime.of(y, m, d, h, min).atZone(calendar).toInstant()

    private val now
        get() = date(2026, 10, 28, 7, 30)

    private fun task(
        id: String,
        due: Instant? = null,
        hint: String? = null,
        hasTime: Boolean? = null,
        done: Boolean = false,
        doneAt: Instant? = null,
    ) =
        ThoughtTask(
            id = id,
            text = "Aufgabe $id",
            dueHint = hint,
            dueAt = due,
            dueHasTime = hasTime,
            done = done,
            doneAt = doneAt,
            owner = Owner.ai,
        )

    private fun thought(
        id: String,
        created: Instant = date(2026, 10, 26, 9),
        topic: String? = "t_a",
        tasks: List<ThoughtTask>,
        deleted: Instant? = null,
    ) =
        Thought(
            id = id,
            createdAt = created,
            trigger = ThoughtTrigger.app,
            state = ThoughtState.done,
            title = id,
            topicId = topic,
            tasks = tasks,
            deletedAt = deleted,
        )

    private fun snapshot(digest: TaskDigest, at: Instant = now) =
        TaskSnapshot(
            generatedAt = at,
            openCount = digest.openCount,
            urgentCount = digest.urgentCount,
            doneTodayAt = digest.doneToday,
            dueDates = digest.dueDates,
            items =
                digest.items.map {
                    TaskSnapshot.Item(
                        it.thoughtID,
                        it.taskID,
                        it.text,
                        it.dueAt,
                        it.hasTime,
                        it.topicID,
                        if (it.topicID == null) null else 0x5FB99AL,
                        "wallet",
                    )
                },
        )

    private val sample
        get() =
            listOf(
                thought(
                    "s_new",
                    date(2026, 10, 28, 7),
                    tasks =
                        listOf(
                            task("heute8", date(2026, 10, 28, 8), hasTime = true),
                            task("ohne1"),
                            task("erledigtHeute", done = true, doneAt = date(2026, 10, 28, 6, 45)),
                        ),
                ),
                thought(
                    "s_old",
                    date(2026, 10, 20, 9),
                    tasks =
                        listOf(
                            task("ueberfaellig", date(2026, 10, 27)),
                            task("heuteOhneZeit", date(2026, 10, 28), hasTime = false),
                            task("morgen", date(2026, 10, 29, 9), hasTime = true),
                            task("spaeter", date(2026, 11, 12)),
                            task("ohne2"),
                            task(
                                "erledigtGestern",
                                done = true,
                                doneAt = date(2026, 10, 27, 23, 59),
                            ),
                        ),
                ),
                thought(
                    "s_trash",
                    tasks = listOf(task("weg", date(2026, 10, 28, 9))),
                    deleted = date(2026, 10, 27),
                ),
            )

    private fun digest(limit: Int = 5, pending: Map<TaskKey, Instant> = emptyMap()) =
        TaskDigest(sample, pending, now, calendar, limit)

    @Test
    fun digestListsNextTasksInAgendaOrder() {
        val d = digest()
        assertEquals(
            listOf("ueberfaellig", "heute8", "heuteOhneZeit", "morgen", "spaeter"),
            d.items.map { it.taskID },
        )
        assertEquals(7, d.openCount)
        assertEquals(3, d.urgentCount)
        assertEquals(
            listOf(
                date(2026, 10, 27),
                date(2026, 10, 28, 8),
                date(2026, 10, 28),
                date(2026, 10, 29, 9),
                date(2026, 11, 12),
            ),
            d.dueDates,
        )
        assertEquals(listOf(date(2026, 10, 28, 6, 45)), d.doneToday)
        val all = digest(20)
        assertEquals(
            listOf(
                "ueberfaellig",
                "heute8",
                "heuteOhneZeit",
                "morgen",
                "spaeter",
                "ohne1",
                "ohne2",
            ),
            all.items.map { it.taskID },
        )
        assertFalse(all.items.any { it.taskID == "weg" })
    }

    @Test
    fun digestKnowsSpokenTimes() {
        val hasTime = digest().items.associate { it.taskID to it.hasTime }
        assertEquals(true, hasTime["heute8"])
        assertEquals(false, hasTime["heuteOhneZeit"])
        assertEquals(false, hasTime["ueberfaellig"])
        val legacy =
            thought("s_l", tasks = listOf(task("alt", date(2026, 10, 28, 8), "morgen um 8 Uhr")))
        assertTrue(TaskDigest(listOf(legacy), now = now, calendar = calendar).items.first().hasTime)
    }

    @Test
    fun pendingCompletionsCountAsDone() {
        val tap = date(2026, 10, 28, 7, 20)
        val d = digest(pending = mapOf(TaskKey("s_new", "heute8") to tap))
        assertFalse(d.items.any { it.taskID == "heute8" })
        assertEquals(6, d.openCount)
        assertEquals(2, d.urgentCount)
        assertEquals(listOf(date(2026, 10, 28, 6, 45), tap), d.doneToday)
        assertFalse(date(2026, 10, 28, 8) in d.dueDates)
        assertEquals(
            listOf(date(2026, 10, 28, 6, 45)),
            digest(pending = mapOf(TaskKey("s_new", "erledigtHeute") to tap)).doneToday,
        )
    }

    @Test
    fun emptyAndAllDone() {
        val none = TaskDigest(emptyList(), now = now, calendar = calendar)
        assertEquals(0, none.openCount)
        assertTrue(none.items.isEmpty() && none.doneToday.isEmpty())
        val done =
            TaskDigest(
                listOf(
                    thought(
                        "s_d",
                        tasks = listOf(task("a", done = true, doneAt = date(2026, 10, 28, 7))),
                    ),
                ),
                now = now,
                calendar = calendar,
            )
        assertEquals(0, done.openCount)
        assertEquals(1, done.doneToday.size)
    }

    @Test
    fun planAppliesOnlyOpenTasksOnce() {
        fun r(id: String, t: String, k: String, m: Int) =
            TaskCompletionPlan.Request(id, TaskKey(t, k), date(2026, 10, 28, 7, m))
        val requests =
            listOf(
                r("q2", "s_new", "heute8", 2),
                r("q1", "s_new", "heute8", 1),
                r("q3", "s_old", "erledigtGestern", 3),
                r("q4", "s_trash", "weg", 4),
                r("q5", "s_gone", "x", 5),
                r("q6", "s_old", "nichtda", 6),
                r("q7", "s_old", "morgen", 7),
            )
        val plan = TaskCompletionPlan.make(requests, sample)
        assertEquals(listOf("q1", "q7"), plan.apply.map { it.id })
        assertEquals(setOf("q2", "q3", "q4", "q5", "q6"), plan.ignored.toSet())
        assertEquals(requests.map { it.id }.toSet(), plan.settled.toSet())
        val keys = plan.apply.map { it.key }.toSet()
        val after = sample.map { t ->
            t.copy(
                tasks =
                    t.tasks.map { if (TaskKey(t.id, it.id) in keys) it.copy(done = true) else it },
            )
        }
        assertTrue(TaskCompletionPlan.make(requests, after).apply.isEmpty())
        assertEquals(
            TaskCompletionPlan.Result(emptyList(), emptyList(), emptyList()),
            TaskCompletionPlan.make(emptyList(), sample),
        )
    }

    @Test
    fun countsFollowTheEntryDate() {
        val s = snapshot(digest())
        val atNow = s.counts(now, calendar)
        assertEquals(TaskSnapshot.Counts(7, 3, 1), atNow)
        assertEquals(3, atNow.focus)
        assertEquals(0.25, atNow.progress, 0.0001)
        assertEquals(TaskSnapshot.Counts(7, 4, 0), s.counts(date(2026, 10, 29, 0), calendar))
        val calm =
            TaskSnapshot(
                generatedAt = now,
                openCount = 2,
                urgentCount = 0,
                doneTodayAt = emptyList(),
                dueDates = listOf(date(2026, 11, 3)),
                items = emptyList(),
            )
        assertEquals(2, calm.counts(now, calendar).focus)
        assertEquals(0.0, calm.counts(now, calendar).progress, 0.0)
        assertEquals(
            1.0,
            calm.copy(doneTodayAt = listOf(date(2026, 10, 28, 7))).counts(now, calendar).progress,
            0.0,
        )
    }

    @Test
    fun completingInTheWidgetIsOptimisticAndIdempotent() {
        val s = snapshot(digest())
        val tap = TaskCompletion("s_new", "heute8", date(2026, 10, 28, 7, 25), "q1")
        val next = requireNotNull(s.completing(tap, calendar))
        assertFalse(next.items.any { it.taskID == "heute8" })
        assertEquals(TaskSnapshot.Counts(6, 2, 2), next.counts(now, calendar))
        assertNull(next.completing(tap, calendar))
        assertEquals(next, next.applying(listOf(tap, tap), calendar))
        val wide = snapshot(digest(20))
        val undated = wide.items.first { it.dueAt == null }
        val other =
            requireNotNull(
                wide.completing(TaskCompletion(undated.thoughtID, undated.taskID, now), calendar),
            )
        assertEquals(TaskSnapshot.Counts(6, 3, 2), other.counts(now, calendar))
        assertEquals(wide.dueDates, other.dueDates)
        assertNull(s.completing(TaskCompletion("s_x", "y", now), calendar))
    }

    @Test
    fun optimisticSnapshotMatchesWhatTheAppWritesLater() {
        val s = snapshot(digest())
        val taps =
            listOf(
                TaskCompletion("s_old", "ueberfaellig", date(2026, 10, 28, 7, 21), "a"),
                TaskCompletion("s_new", "heute8", date(2026, 10, 28, 7, 22), "b"),
            )
        val optimistic = s.applying(taps, calendar)
        val app =
            snapshot(digest(pending = taps.associate { TaskKey(it.thoughtID, it.taskID) to it.at }))
        assertEquals(app.openCount, optimistic.openCount)
        assertEquals(app.urgentCount, optimistic.urgentCount)
        assertEquals(app.doneTodayAt, optimistic.doneTodayAt)
        assertEquals(app.dueDates, optimistic.dueDates)
        assertEquals(optimistic.items, app.items.take(optimistic.items.size))
        assertEquals(5, app.items.size)
    }

    @Test
    fun dueLabelsAndLateness() {
        val s = snapshot(digest(20))
        fun due(id: String, at: Instant = now) = s.items.first { it.taskID == id }.due(at, calendar)
        assertEquals(TaskSnapshot.Item.Due.Day.Past(1), due("ueberfaellig")?.day)
        assertEquals(true, due("ueberfaellig")?.isLate)
        assertEquals(TaskSnapshot.Item.Due.Day.Today, due("heute8")?.day)
        assertEquals(false, due("heute8")?.isLate)
        assertEquals(true, due("heute8", date(2026, 10, 28, 8))?.isLate)
        assertEquals(false, due("heuteOhneZeit", date(2026, 10, 28, 23, 59))?.isLate)
        assertEquals(true, due("heuteOhneZeit", date(2026, 10, 29, 0))?.isLate)
        assertEquals(TaskSnapshot.Item.Due.Day.Tomorrow, due("morgen")?.day)
        assertEquals(true, due("morgen")?.showsTime)
        assertEquals(TaskSnapshot.Item.Due.Day.Today, due("morgen", date(2026, 10, 29, 0))?.day)
        assertEquals(TaskSnapshot.Item.Due.Day.Later, due("spaeter")?.day)
        assertEquals(TaskSnapshot.Item.Due.Day.Weekday, due("spaeter", date(2026, 11, 8))?.day)
        assertNull(due("ohne1"))
    }

    @Test
    fun timelineHasDueTimesAndMidnights() {
        val s = snapshot(digest())
        assertEquals(
            listOf(
                now,
                date(2026, 10, 28, 8),
                date(2026, 10, 29, 0),
                date(2026, 10, 29, 9),
                date(2026, 10, 30, 0),
            ),
            s.timelineDates(now, calendar),
        )
        val later = s.timelineDates(date(2026, 10, 28, 8, 30), calendar)
        assertFalse(date(2026, 10, 28, 8) in later)
        assertEquals(date(2026, 10, 28, 8, 30), later.first())
        assertEquals(2, s.timelineDates(now, calendar, limit = 2).size)
        val start = date(2026, 3, 28, 22)
        assertEquals(
            listOf(start, date(2026, 3, 29, 0), date(2026, 3, 30, 0)),
            TaskSnapshot.empty(start).timelineDates(start, calendar),
        )
    }

    @Test
    fun nextTimedIsTodayOnly() {
        val s = snapshot(digest())
        assertEquals("heute8", s.nextTimed(now, calendar)?.taskID)
        assertNull(s.nextTimed(date(2026, 10, 28, 8, 1), calendar))
        assertEquals("morgen", s.nextTimed(date(2026, 10, 29, 0), calendar)?.taskID)
    }

    @Test
    fun roundTripAndSameContent() {
        val s = snapshot(digest(), now.plusNanos(123456000))
        assertEquals(s, ThoughtJSON.decode<TaskSnapshot>(ThoughtJSON.encode(s)))
        val later = s.copy(generatedAt = s.generatedAt.plusSeconds(60))
        assertTrue(later.sameContent(s))
        assertFalse(later.copy(openCount = later.openCount + 1).sameContent(s))
        assertFalse(s.sameContent(null))
        val c = TaskCompletion("s_a", "k_b", now.plusMillis(500))
        assertEquals(c, ThoughtJSON.decode<TaskCompletion>(ThoughtJSON.encode(c)))
    }

    @Test
    fun authSettingDefaultsToOn() {
        assertTrue(TaskWidgetSettings.requiresAuth(emptyMap()))
        assertTrue(TaskWidgetSettings.requiresAuth(null))
        assertFalse(
            TaskWidgetSettings.requiresAuth(mapOf(TaskWidgetSettings.requireAuthKey to false)),
        )
        assertEquals("paply.tasks.requireAuth", TaskWidgetSettings.requireAuthKey)
    }
}
