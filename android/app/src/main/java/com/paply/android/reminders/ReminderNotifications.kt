package com.paply.android.reminders

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.paply.android.MainActivity
import com.paply.android.R
import com.paply.thoughts.display.TaskReminder

internal class ReminderNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    init {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Erinnerungen", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Aufgaben mit einer Uhrzeit"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
    }

    fun allowed(): Boolean = (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context,
        Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && manager.areNotificationsEnabled() &&
        manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE

    fun post(reminder: TaskReminder, stamp: String) {
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = ReminderLinks.uri(reminder.thoughtID, reminder.taskID)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val public = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_mic)
            .setContentTitle("Paply-Erinnerung").setVisibility(NotificationCompat.VISIBILITY_PUBLIC).build()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_mic).setContentTitle(reminder.title).setContentText(reminder.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(reminder.body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(public).setAutoCancel(true).setOnlyAlertOnce(true).setContentIntent(open)
            .addAction(0, "Erledigt", action(reminder.id, stamp, ACTION_DONE))
            .addAction(0, "In 1 Stunde", action(reminder.id, stamp, ACTION_SNOOZE))
            .build()
        manager.notify(reminder.id, NOTIFICATION_ID, notification)
    }

    fun cancel(id: String) = manager.cancel(id, NOTIFICATION_ID)
    fun delivered(): List<String> = manager.activeNotifications.filter { it.id == NOTIFICATION_ID }.mapNotNull { it.tag }

    private fun action(id: String, stamp: String, action: String): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, ReminderActionReceiver::class.java).apply {
            this.action = action
            data = Uri.Builder().scheme("paply-reminder").authority("action").appendPath(action).appendPath(id).build()
            putExtra(ReminderAlarms.EXTRA_ID, id); putExtra(ReminderAlarms.EXTRA_STAMP, stamp)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    companion object {
        const val CHANNEL = "paply.task-reminders"
        const val NOTIFICATION_ID = 3104
        const val ACTION_DONE = "com.paply.android.reminders.DONE"
        const val ACTION_SNOOZE = "com.paply.android.reminders.SNOOZE"
    }
}

/** Explicit app intents only; no exported web deep link or task text in the URI. */
object ReminderLinks {
    fun uri(thoughtID: String, taskID: String): Uri = Uri.Builder().scheme("paply").authority("task")
        .appendPath(thoughtID).appendPath(taskID).build()

    fun parse(intent: Intent?): com.paply.thoughts.display.TaskKey? {
        val uri = intent?.data ?: return null
        if (intent.action != Intent.ACTION_VIEW || uri.scheme != "paply" || uri.host != "task" || uri.pathSegments.size != 2) return null
        return com.paply.thoughts.display.TaskReminderPlan.parse("task/${uri.pathSegments[0]}/${uri.pathSegments[1]}")
    }
}
