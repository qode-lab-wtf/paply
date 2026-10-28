package com.paply.android.reminders

import android.app.Notification
import android.app.NotificationManager
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.BuildConfig
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.*
import com.paply.thoughts.display.TaskReminderPlan
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Run individual methods on paply3 only. Debug fixtures are fully processed local thoughts, never sent to AI. */
class ReminderDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val repository get() = ThoughtsRepository.get(context)
    private val reminders get() = TaskReminders.get(context)
    private val manager get() = context.getSystemService(NotificationManager::class.java)

    @Test fun seedReminderInTwoMinutes() = runBlocking {
        check(BuildConfig.DEBUG)
        check(KeyVault(context).read() == null) { "Use paply3 without a Groq key" }
        SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
        val store = repository.backend().store
        store.purge(store.all().filter { it.id.startsWith("s_rem_") }.map { it.id })
        val now = Instant.now()
        val due = now.plusSeconds(120).let { Instant.ofEpochSecond(it.epochSecond) }
        val later = now.plusSeconds(1800).let { Instant.ofEpochSecond(it.epochSecond) }
        store.save(Thought(id = "s_rem_test", trigger = ThoughtTrigger.app, state = ThoughtState.done,
            title = "Erinnerung ausprobieren", text = "Briefe bearbeiten und später die Pflanzen gießen.", tasks = listOf(
                ThoughtTask(id = "k_rem_two", text = "Briefe bearbeiten", dueAt = due, dueHasTime = true, owner = Owner.ai),
                ThoughtTask(id = "k_rem_boot", text = "Pflanzen gießen", dueAt = later, dueHasTime = true, owner = Owner.ai),
                ThoughtTask(id = "k_rem_day", text = "Nur ein Tag bleibt still", dueAt = later, dueHasTime = false, owner = Owner.ai))))
        repository.publish(store)
        reminders.setEnabled(true)
        reminders.reconcile(force = true)
        File(context.filesDir, "reminder-test-result.json").writeText(JSONObject()
            .put("due", due.toString()).put("seededAt", now.toString()).put("later", later.toString()).toString())
        assertEquals(2, reminders.state.value.plannedCount)
    }

    @Test fun verifyDeliveredPrivacy() {
        val note = manager.activeNotifications.first { it.tag == "task/s_rem_test/k_rem_two" }.notification
        assertEquals(Notification.VISIBILITY_PRIVATE, note.visibility)
        assertEquals("Paply-Erinnerung", note.publicVersion.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString())
        assertEquals(listOf("Erledigt", "In 1 Stunde"), note.actions.map { it.title.toString() })
        assertEquals("Erinnerungen", manager.getNotificationChannel(note.channelId).name.toString())
        assertNotNull(note.contentIntent)
    }

    @Test fun verifyCompletedFromNotification() = runBlocking {
        val task = repository.thought("s_rem_test")!!.tasks.first { it.id == "k_rem_two" }
        assertTrue(task.done); assertNotNull(task.doneAt)
        reminders.reconcile()
        assertEquals(1, reminders.state.value.plannedCount)
        assertFalse(manager.activeNotifications.any { it.tag == "task/s_rem_test/k_rem_two" })
    }

    @Test fun snoozeFromNotificationPersistsAndKeepsTaskOpen() = runBlocking {
        val note = manager.activeNotifications.first { it.tag == "task/s_rem_test/k_rem_two" }.notification
        val before = Instant.now()
        note.actions.first { it.title == "In 1 Stunde" }.actionIntent.send()
        val journal = ReminderStore(File(context.noBackupFilesDir, "reminders/state.json"))
        withTimeout(5000) {
            while (journal.load().snoozes["task/s_rem_test/k_rem_two"] == null) delay(50)
        }
        val snooze = journal.load().snoozes.getValue("task/s_rem_test/k_rem_two")
        assertTrue(snooze.fireAt >= before.plusSeconds(3599)); assertTrue(snooze.fireAt <= Instant.now().plusSeconds(3600))
        assertFalse(repository.thought("s_rem_test")!!.tasks.first { it.id == "k_rem_two" }.done)
        reminders.reconcile()
        assertTrue(journal.load().records.getValue("task/s_rem_test/k_rem_two").reminder.snoozed)
    }

    @Test fun betaOffCancelsAndOnRestoresAndCompletionIsIdempotent() = runBlocking {
        SettingsRepository.get(context).update { it.copy(betaThoughts = false) }
        reminders.reconcile()
        assertEquals(0, reminders.state.value.plannedCount)
        assertFalse(manager.activeNotifications.any { TaskReminderPlan.parse(it.tag ?: "") != null })
        SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
        reminders.reconcile()
        assertTrue(reminders.state.value.plannedCount > 0)
        repository.completeTaskFromReminder("s_rem_test", "k_rem_boot")
        val once = repository.thought("s_rem_test")!!.tasks.first { it.id == "k_rem_boot" }
        repository.completeTaskFromReminder("s_rem_test", "k_rem_boot")
        assertEquals(once, repository.thought("s_rem_test")!!.tasks.first { it.id == "k_rem_boot" })
        reminders.reconcile()
    }

    @Test fun deepLinkCallbackKeepsColdRequestUntilConsumed() = runBlocking {
        val link = android.content.Intent(android.content.Intent.ACTION_VIEW, ReminderLinks.uri("s_rem_test", "k_rem_two"))
        val key = requireNotNull(ReminderLinks.parse(link))
        repository.openTaskFromReminder(key)
        assertEquals(key, repository.reminderDestination.value)
        repository.consumeReminderDestination(key)
        assertNull(repository.reminderDestination.value)
        assertNull(ReminderLinks.parse(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("paply://task/one"))))
    }

    @Test fun snoozeAndDoneUseRealBroadcastsAndDurableRepository() = runBlocking {
        check(BuildConfig.DEBUG && KeyVault(context).read() == null)
        val thoughtID = "s_rem_actions"
        val taskID = "k_rem_actions"
        val id = TaskReminderPlan.identifier(thoughtID, taskID)
        val store = repository.backend().store
        val journal = ReminderStore(File(context.noBackupFilesDir, "reminders/state.json"))
        try {
            store.save(Thought(id = thoughtID, trigger = ThoughtTrigger.app, state = ThoughtState.done, title = "Aktionstest",
                tasks = listOf(ThoughtTask(id = taskID, text = "Später abhaken", dueAt = Instant.now().plusSeconds(3600), dueHasTime = true, owner = Owner.ai))))
            repository.publish(store)
            reminders.setEnabled(true)
            var record = journal.load().records.getValue(id)
            reminders.deliver(id, record.stamp) // Fixture delivery; subsequent actions are real platform PendingIntents.
            val before = Instant.now()
            manager.activeNotifications.first { it.tag == id }.notification.actions.first { it.title == "In 1 Stunde" }.actionIntent.send()
            withTimeout(5000) { while (journal.load().records[id]?.reminder?.snoozed != true) delay(50) }
            val later = journal.load().snoozes.getValue(id).fireAt
            assertTrue(later >= before.plusSeconds(3599))
            assertFalse(repository.thought(thoughtID)!!.tasks.single().done)
            SettingsRepository.get(context).update { it.copy(betaThoughts = false) }
            reminders.reconcile()
            assertEquals(0, reminders.state.value.plannedCount)
            assertEquals(later, journal.load().snoozes[id]?.fireAt)
            SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
            reminders.reconcile()
            record = journal.load().records.getValue(id)
            assertEquals(later, record.reminder.fireAt)
            reminders.deliver(id, record.stamp)
            val done = manager.activeNotifications.first { it.tag == id }.notification.actions.first { it.title == "Erledigt" }.actionIntent
            done.send(); done.send()
            withTimeout(5000) { while (repository.thought(thoughtID)?.tasks?.single()?.done != true) delay(50) }
            reminders.reconcile()
            assertFalse(journal.load().records.containsKey(id))
            assertFalse(manager.activeNotifications.any { it.tag == id })
        } finally {
            SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
            repository.permanentlyDelete(thoughtID)
            reminders.reconcile()
        }
    }
}
