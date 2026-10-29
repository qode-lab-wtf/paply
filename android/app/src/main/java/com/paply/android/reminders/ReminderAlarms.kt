package com.paply.android.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.paply.thoughts.display.TaskReminder
import java.time.Instant

internal class ReminderAlarms(private val context: Context) {
    private val manager = context.getSystemService(AlarmManager::class.java)
    fun canScheduleExact() = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()

    fun exactAccessIntent(): Intent? = if (Build.VERSION.SDK_INT >= 31 && !canScheduleExact())
        Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            Uri.fromParts("package", context.packageName, null)) else null

    fun schedule(reminder: TaskReminder, stamp: String, now: Instant) {
        val operation = operation(reminder.id, stamp, PendingIntent.FLAG_UPDATE_CURRENT)!!
        if (canScheduleExact()) {
            try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.fireAt.toEpochMilli(), operation)
                return
            } catch (_: SecurityException) { /* Special access can be revoked between checking and scheduling. */ }
        }
        val timing = ReminderPlanning.timing(reminder.fireAt, now, exact = false)
        manager.setWindow(AlarmManager.RTC_WAKEUP, timing.startMillis, timing.windowMillis, operation)
    }

    fun cancel(id: String) {
        operation(id, null, PendingIntent.FLAG_NO_CREATE)?.let { manager.cancel(it); it.cancel() }
    }

    private fun operation(id: String, stamp: String?, flags: Int): PendingIntent? = PendingIntent.getBroadcast(context, 0,
        Intent(context, ReminderAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            // PendingIntent identity uses the complete ID, never String.hashCode (collisions lose reminders).
            data = Uri.Builder().scheme("paply-reminder").authority("alarm").appendPath(id).build()
            putExtra(EXTRA_ID, id); putExtra(EXTRA_STAMP, stamp)
        }, flags or PendingIntent.FLAG_IMMUTABLE)

    companion object {
        const val ACTION_FIRE = "com.paply.android.reminders.FIRE"
        const val EXTRA_ID = "reminderId"
        const val EXTRA_STAMP = "reminderStamp"
    }
}
