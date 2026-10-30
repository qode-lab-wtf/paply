package com.paply.android.reminders

import android.util.AtomicFile
import com.paply.thoughts.display.TaskReminder
import com.paply.thoughts.display.TaskReminderPlan
import java.io.File
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

internal data class ReminderRecord(val reminder: TaskReminder, val stamp: String, val pending: Boolean = true,
    val delivered: Boolean = false, val deliverable: Boolean = true)

internal data class ReminderData(
    // Recording may already have notification permission. Reminders still require their own invitation/switch.
    val enabled: Boolean = false,
    val asked: Boolean = false,
    val hiddenUntil: Instant? = null,
    val records: Map<String, ReminderRecord> = emptyMap(),
    val snoozes: Map<String, TaskReminderPlan.Snooze> = emptyMap(),
)

/** Atomic, local-only journal. Written before AlarmManager, so an interrupted schedule is recoverable. */
internal class ReminderStore(file: File) {
    private val atomic = AtomicFile(file)
    fun load(): ReminderData {
        if (!atomic.baseFile.exists() && !File(atomic.baseFile.path + ".bak").exists()) return ReminderData()
        return atomic.openRead().use { decode(it.readBytes().toString(Charsets.UTF_8)) }
    }
    fun save(data: ReminderData) {
        check(atomic.baseFile.parentFile?.let { it.isDirectory || it.mkdirs() } == true)
        val stream = atomic.startWrite()
        try { stream.write(encode(data).toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (e: Exception) { atomic.failWrite(stream); throw e }
    }

    companion object {
        internal fun encode(data: ReminderData): String = JSONObject().apply {
            put("version", 1); put("enabled", data.enabled); put("asked", data.asked)
            data.hiddenUntil?.let { put("hiddenUntil", it.toEpochMilli()) }
            put("records", JSONArray().apply { data.records.values.forEach { record ->
                val r = record.reminder
                put(JSONObject().apply {
                    put("id", r.id); put("thought", r.thoughtID); put("task", r.taskID)
                    put("fire", r.fireAt.toEpochMilli()); put("due", r.dueAt.toEpochMilli()); put("snoozed", r.snoozed)
                    put("title", r.title); put("body", r.body); put("thread", r.threadID)
                    put("stamp", record.stamp); put("pending", record.pending); put("delivered", record.delivered); put("deliverable", record.deliverable)
                })
            } })
            put("snoozes", JSONObject().apply { data.snoozes.forEach { (id, s) ->
                put(id, JSONObject().put("fire", s.fireAt.toEpochMilli()).put("due", s.dueAt.toEpochMilli()))
            } })
        }.toString()

        internal fun decode(text: String): ReminderData {
            val o = JSONObject(text)
            require(o.getInt("version") == 1)
            val records = o.getJSONArray("records").let { a -> (0 until a.length()).associate { index ->
                val r = a.getJSONObject(index)
                val reminder = TaskReminder(r.getString("id"), r.getString("thought"), r.getString("task"),
                    Instant.ofEpochMilli(r.getLong("fire")), Instant.ofEpochMilli(r.getLong("due")), r.getBoolean("snoozed"),
                    r.getString("title"), r.getString("body"), r.getString("thread"))
                require(TaskReminderPlan.identifier(reminder.thoughtID, reminder.taskID) == reminder.id)
                reminder.id to ReminderRecord(reminder, r.getString("stamp"), r.getBoolean("pending"), r.getBoolean("delivered"), r.getBoolean("deliverable"))
            } }
            val snoozes = o.getJSONObject("snoozes").let { s -> s.keys().asSequence().associateWith { id ->
                val entry = s.getJSONObject(id)
                TaskReminderPlan.Snooze(Instant.ofEpochMilli(entry.getLong("fire")), Instant.ofEpochMilli(entry.getLong("due")))
            } }
            return ReminderData(o.getBoolean("enabled"), o.getBoolean("asked"),
                if (o.has("hiddenUntil")) Instant.ofEpochMilli(o.getLong("hiddenUntil")) else null, records, snoozes)
        }
    }
}
