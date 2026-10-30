package com.paply.android.reminders

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import com.paply.android.Diag
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.display.TaskReminderPlan
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class ReminderState(val enabled: Boolean = false, val asked: Boolean = false, val hiddenUntil: Instant? = null,
    val notificationsAllowed: Boolean = false, val exactAllowed: Boolean = false, val beta: Boolean = true,
    val plannedCount: Int = 0, val error: String? = null) {
    val isOn get() = enabled && notificationsAllowed
}

/** One process-wide, serialized path for planning, delivery, completion and snooze. Never asks permission on startup. */
class TaskReminders private constructor(private val app: Context, private val repository: ThoughtsRepository) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val alarms = ReminderAlarms(app)
    private val notifications = ReminderNotifications(app)
    private val storeFile = File(app.noBackupFilesDir, "reminders/state.json")
    private val store = ReminderStore(storeFile)
    private var data = try { store.load() } catch (_: Exception) {
        // Fail closed. Preserve the unreadable journal for diagnosis, never infer permission from it.
        storeFile.renameTo(File(storeFile.parentFile, "damaged-${System.currentTimeMillis()}.json"))
        ReminderData()
    }
    private val mutableState = MutableStateFlow(ReminderState())
    val state: StateFlow<ReminderState> = mutableState.asStateFlow()
    private val requests = Channel<Unit>(Channel.CONFLATED)
    private val forceNext = AtomicBoolean(false)

    init {
        refreshState()
        scope.launch {
            for (ignored in requests) {
                try { mutex.withLock { reconcileLocked(forceNext.getAndSet(false)) } }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { reportFailure() }
            }
        }
        scope.launch {
            combine(repository.isLoaded, repository.thoughts, repository.deleted, repository.topics) { loaded, _, _, _ -> loaded }
                .filter { it }.collect { requestReconcile() }
        }
        scope.launch {
            SettingsRepository.get(app).state.map { it.betaThoughts }.distinctUntilChanged().collect { requestReconcile() }
        }
        (app as? Application)?.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { requestReconcile() }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
        // Re-register persisted alarms, including after backup/restore or an interrupted AlarmManager call.
        requestReconcile(force = true)
    }

    fun requestReconcile(force: Boolean = false) {
        if (force) forceNext.set(true)
        requests.trySend(Unit)
    }

    suspend fun reconcile(force: Boolean = false) = mutex.withLock { reconcileLocked(force) }

    suspend fun setEnabled(enabled: Boolean) = mutex.withLock {
        persist(data.copy(enabled = enabled, asked = data.asked || enabled))
        reconcileLocked()
    }

    suspend fun dismissInvitation(now: Instant = Instant.now()) = mutex.withLock {
        persist(data.copy(hiddenUntil = now.plusSeconds(ReminderPlanning.INVITATION_PAUSE_SECONDS)))
        refreshState()
    }

    private fun access() = ReminderPlanning.Access(SettingsRepository.get(app).state.value.betaThoughts,
        data.enabled, notifications.allowed(), alarms.canScheduleExact())

    private fun persist(next: ReminderData) { store.save(next); data = next }

    private fun refreshState() {
        val access = access()
        mutableState.value = ReminderState(data.enabled, data.asked, data.hiddenUntil, access.notifications,
            access.exact, access.beta, data.records.values.count { it.pending })
    }

    private fun reportFailure() {
        mutableState.update { it.copy(error = "Erinnerungen konnten nicht aktualisiert werden. Bitte Paply erneut öffnen.") }
        Diag.event("reminders.failed")
    }

    private suspend fun reconcileLocked(force: Boolean = false) {
        val access = access()
        // Turning off does not wait for a possibly unavailable repository.
        if (!access.allowed) {
            val pending = data.records.filterValues { it.pending }.keys
            pending.forEach(alarms::cancel)
            notifications.delivered().filter { TaskReminderPlan.parse(it) != null }.forEach(notifications::cancel)
            persist(data.copy(records = data.records.mapValues { it.value.copy(pending = false, deliverable = false) }))
            refreshState()
            return
        }
        val snapshot = repository.reminderSnapshot()
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val update = reconcileReminders(data, snapshot.thoughts, snapshot.topicsByThought, access(), now, zone, force)
        // Journal first; startup force-reconciliation repairs a process death before the platform calls.
        persist(update.data)
        val scheduled = mutableSetOf<String>()
        try {
            update.cancel.forEach(alarms::cancel)
            for (reminder in update.schedule) {
                if (!access().allowed) break
                alarms.schedule(reminder, data.records.getValue(reminder.id).stamp, now)
                scheduled += reminder.id
            }
        } catch (e: Exception) {
            // A failed platform call must not look idempotently scheduled on the next foreground/change event.
            val retry = update.schedule.map { it.id }.toSet() - scheduled
            persist(data.copy(records = data.records.mapValues { (id, r) -> if (id in retry) r.copy(pending = false) else r }))
            throw e
        }
        // OFF wins even when it arrived while waiting for repository IO or during scheduling.
        if (!access().allowed) { reconcileLocked(); return }
        val stale = TaskReminderPlan.removableDelivered(notifications.delivered(), snapshot.thoughts, featureOn = true)
        stale.forEach(notifications::cancel)
        refreshState()
        if (update.schedule.isNotEmpty() || update.cancel.isNotEmpty() || stale.isNotEmpty())
            Diag.event("reminders.reconcile scheduled=${update.schedule.size} canceled=${update.cancel.size} exact=${alarms.canScheduleExact()}")
    }

    internal suspend fun deliver(id: String, stamp: String) = mutex.withLock {
        val record = data.records[id] ?: return@withLock
        if (record.stamp != stamp || record.delivered || !record.deliverable || !access().allowed) return@withLock
        val snapshot = repository.reminderSnapshot()
        if (!ReminderPlanning.stillApplies(record.reminder, snapshot.thoughts, data.snoozes, ZoneId.systemDefault()) || !access().allowed) {
            reconcileLocked(); return@withLock
        }
        notifications.post(record.reminder, stamp)
        persist(data.copy(records = data.records + (id to record.copy(pending = false, delivered = true))))
        alarms.cancel(id)
        refreshState()
        // Fill the next slot when iOS's existing next-50 plan had more tasks waiting.
        requestReconcile()
        Diag.event("reminders.delivered")
    }

    internal suspend fun handleAction(id: String, stamp: String, action: String) = mutex.withLock {
        val key = TaskReminderPlan.parse(id) ?: return@withLock
        val record = data.records[id] ?: return@withLock
        if (record.stamp != stamp || !record.delivered) return@withLock
        if (!SettingsRepository.get(app).state.value.betaThoughts) { reconcileLocked(); return@withLock }
        val snapshot = repository.reminderSnapshot()
        if (!ReminderPlanning.stillApplies(record.reminder, snapshot.thoughts, data.snoozes, ZoneId.systemDefault())) {
            notifications.cancel(id); reconcileLocked(); return@withLock
        }
        when (action) {
            ReminderNotifications.ACTION_DONE -> repository.completeTaskFromReminder(key.thoughtID, key.taskID)
            ReminderNotifications.ACTION_SNOOZE -> {
                if (!access().allowed || !TaskReminderPlan.maySnooze(key.thoughtID, key.taskID,
                        TaskReminderPlan.SnoozeFacts(snapshot.thoughts, queued = false, inSnapshot = null, locked = false))) return@withLock
                persist(data.copy(snoozes = data.snoozes + (id to TaskReminderPlan.Snooze(
                    TaskReminderPlan.snoozed(Instant.now()), record.reminder.dueAt))))
            }
            else -> return@withLock
        }
        notifications.cancel(id)
        reconcileLocked()
        Diag.event("reminders.action done=${action == ReminderNotifications.ACTION_DONE}")
    }

    companion object {
        @android.annotation.SuppressLint("StaticFieldLeak") // Application context only.
        @Volatile private var instance: TaskReminders? = null
        internal fun start(context: Context, repository: ThoughtsRepository): TaskReminders = instance ?: synchronized(this) {
            instance ?: TaskReminders(context.applicationContext, repository).also { instance = it }
        }
        fun get(context: Context): TaskReminders {
            val repository = ThoughtsRepository.get(context)
            return start(context, repository)
        }
    }
}
