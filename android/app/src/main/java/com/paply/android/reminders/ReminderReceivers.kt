package com.paply.android.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import com.paply.android.Diag
import kotlinx.coroutines.*

private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/** goAsync keeps a cold process alive; the bounded wake lock covers IO after onReceive returns. */
private fun BroadcastReceiver.runAsync(context: Context, action: suspend () -> Unit) {
    val pending = goAsync()
    val lock = context.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Paply:reminder")
    lock.acquire(10_000)
    receiverScope.launch {
        try { withTimeout(8_000) { action() } }
        catch (_: Exception) { Diag.event("reminders.receiver.failed") }
        finally { if (lock.isHeld) lock.release(); pending.finish() }
    }
}

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ReminderAlarms.ACTION_FIRE) return
        val id = intent.getStringExtra(ReminderAlarms.EXTRA_ID) ?: return
        val stamp = intent.getStringExtra(ReminderAlarms.EXTRA_STAMP) ?: return
        runAsync(context) { TaskReminders.get(context).deliver(id, stamp) }
    }
}

class ReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action?.takeIf { it == ReminderNotifications.ACTION_DONE || it == ReminderNotifications.ACTION_SNOOZE } ?: return
        val id = intent.getStringExtra(ReminderAlarms.EXTRA_ID) ?: return
        val stamp = intent.getStringExtra(ReminderAlarms.EXTRA_STAMP) ?: return
        runAsync(context) { TaskReminders.get(context).handleAction(id, stamp, action) }
    }
}

class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_MY_PACKAGE_REPLACED, "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) return
        runAsync(context) { TaskReminders.get(context).reconcile(force = true) }
    }
}
