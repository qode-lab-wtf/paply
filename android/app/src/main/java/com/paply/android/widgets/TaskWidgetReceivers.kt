package com.paply.android.widgets

import android.app.KeyguardManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import com.paply.android.Diag
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtsRepository
import kotlinx.coroutines.*

private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

private fun BroadcastReceiver.widgetAsync(context: Context, block: suspend () -> Unit) {
    val pending = goAsync()
    val lock = context.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Paply:task-widget")
    lock.acquire(10_000)
    receiverScope.launch {
        try { withTimeout(8_000) { block() } }
        catch (_: Exception) { Diag.event("task-widget.receiver.failed") }
        finally { if (lock.isHeld) lock.release(); pending.finish() }
    }
}

open class TaskWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        widgetAsync(context) { TaskWidgets.get(context).update() }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        widgetAsync(context) { TaskWidgets.get(context).update() }
    }
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        widgetAsync(context) { TaskWidgets.get(context).update() }
    }
}
class TaskSmallWidget : TaskWidgetProvider()
class TaskMediumWidget : TaskWidgetProvider()

/** Private immutable broadcasts, idempotent completion, cold repository awaited within goAsync. */
class TaskWidgetActions : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DONE) return
        val parts = intent.data?.takeIf { it.scheme == "paply-widget" && it.host == "complete" }?.pathSegments ?: return
        if (parts.size != 2 || parts.any { it.isBlank() }) return
        widgetAsync(context) {
            if (SettingsRepository.get(context).state.value.betaThoughts &&
                !context.getSystemService(KeyguardManager::class.java).isDeviceLocked) {
                // Shared idempotent repository action also prevents stale widgets changing trashed thoughts.
                ThoughtsRepository.get(context).completeTaskFromReminder(parts[0], parts[1])
            }
            TaskWidgets.get(context).update()
        }
    }
    companion object {
        private const val DONE = "com.paply.android.widgets.COMPLETE"
        internal fun complete(context: Context, thoughtID: String, taskID: String): PendingIntent =
            PendingIntent.getBroadcast(context, 0, Intent(context, TaskWidgetActions::class.java).apply {
                action = DONE
                data = Uri.Builder().scheme("paply-widget").authority("complete").appendPath(thoughtID).appendPath(taskID).build()
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class TaskWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in setOf(Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_BOOT_COMPLETED)) {
            widgetAsync(context) { TaskWidgets.get(context).update() }
        }
    }
}
