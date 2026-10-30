package com.paply.android.widgets

import com.paply.thoughts.Thought
import com.paply.thoughts.ThoughtState
import com.paply.thoughts.Topic
import com.paply.thoughts.display.TaskDigest
import com.paply.thoughts.display.TaskSnapshot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Pure widget projection: all selection/order comes from the shared iOS-port TaskDigest. */
data class TaskWidgetContent(val snapshot: TaskSnapshot?, val note: String? = null) {
    val openCount get() = snapshot?.openCount
    fun items(medium: Boolean) = snapshot?.items.orEmpty().take(if (medium) 3 else 1)

    companion object {
        const val BETA_OFF = "In Paply unter Beta einschalten"
        const val LOCKED = "Aufgaben nach dem Entsperren in Paply öffnen"
        fun make(thoughts: List<Thought>, topics: Map<String, Topic> = emptyMap(), beta: Boolean,
            loaded: Boolean = true, keyguard: Boolean = false, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): TaskWidgetContent {
            // Fail closed, including count, even if a host ignores our not_keyguard category.
            if (keyguard) return TaskWidgetContent(null, LOCKED)
            if (!beta) return TaskWidgetContent(null, BETA_OFF)
            if (!loaded) return TaskWidgetContent(null, "Öffne Paply einmal – dann stehen deine Aufgaben hier.")
            val digest = TaskDigest(thoughts.filter { it.state != ThoughtState.empty && it.state != ThoughtState.recording }, now = now, calendar = zone)
            val snapshot = TaskSnapshot(generatedAt = now, openCount = digest.openCount, urgentCount = digest.urgentCount,
                doneTodayAt = digest.doneToday, dueDates = digest.dueDates, items = digest.items.map {
                    TaskSnapshot.Item(it.thoughtID, it.taskID, it.text, it.dueAt, it.hasTime, topicTitle = topics[it.thoughtID]?.title)
                })
            return TaskWidgetContent(snapshot, if (digest.openCount == 0) "Alles erledigt" else null)
        }
        fun due(item: TaskSnapshot.Item, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String? {
            val due = item.due(now, zone) ?: return item.topicTitle
            val date = due.date.atZone(zone)
            fun format(pattern: String) = DateTimeFormatter.ofPattern(pattern, Locale.GERMAN).format(date)
            val time = if (due.showsTime) " ${format("HH:mm")}" else ""
            return when (val day = due.day) {
                is TaskSnapshot.Item.Due.Day.Past -> if (day.days == 1) "Gestern" else format("d. MMM")
                TaskSnapshot.Item.Due.Day.Today -> if (due.showsTime) format("HH:mm") else "Heute"
                TaskSnapshot.Item.Due.Day.Tomorrow -> "Morgen$time"
                TaskSnapshot.Item.Due.Day.Weekday -> format("EE") + time
                TaskSnapshot.Item.Due.Day.Later -> format("d. MMM") + time
            }
        }
    }
}
