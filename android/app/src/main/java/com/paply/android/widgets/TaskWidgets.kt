package com.paply.android.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import androidx.compose.ui.graphics.toArgb
import androidx.work.*
import com.paply.android.Diag
import com.paply.android.MainActivity
import com.paply.android.R
import com.paply.android.reminders.ReminderLinks
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.theme.PaplyColors as C
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** No polling: store/beta changes are coalesced; one persisted job at the next due time/midnight. */
class TaskWidgets private constructor(private val app: Context, private val repository: ThoughtsRepository) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val manager = AppWidgetManager.getInstance(app)
    private var scheduledAt: Instant? = null

    init {
        scope.launch {
            combine(repository.thoughts, repository.topics, repository.isLoaded, SettingsRepository.get(app).state) { _, _, loaded, prefs ->
                loaded to prefs.betaThoughts
            }.conflate().collect {
                // Fixed coalescing window also makes progress while changes keep arriving.
                delay(400)
                try { update() } catch (e: CancellationException) { throw e }
                catch (_: Exception) { Diag.event("task-widget.update.failed") }
            }
        }
    }

    suspend fun update(fromWorker: Boolean = false) = mutex.withLock {
        val ids = listOf(TaskSmallWidget::class.java to false, TaskMediumWidget::class.java to true).flatMap { (type, medium) ->
            manager.getAppWidgetIds(ComponentName(app, type)).map { it to medium }
        }
        if (ids.isEmpty()) {
            WorkManager.getInstance(app).cancelUniqueWork(WORK_NAME)
            scheduledAt = null
            return@withLock
        }
        val now = Instant.now()
        val beta = SettingsRepository.get(app).state.value.betaThoughts
        val snapshot = if (beta) repository.reminderSnapshot() else null
        val content = TaskWidgetContent.make(snapshot?.thoughts.orEmpty(), snapshot?.topicsByThought.orEmpty(), beta, now = now)
        for ((id, medium) in ids) {
            val keyguard = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY) and
                AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD != 0
            val safe = if (keyguard) TaskWidgetContent(null, TaskWidgetContent.LOCKED) else content
            manager.updateAppWidget(id, views(app, safe, medium, now))
        }
        val next = content.snapshot?.timelineDates(now)?.firstOrNull { it > now }
        if (next == null || next != scheduledAt) {
            val work = WorkManager.getInstance(app)
            if (next == null) work.cancelUniqueWork(WORK_NAME)
            else work.enqueueUniqueWork(WORK_NAME, if (fromWorker) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<TaskWidgetRefreshWorker>()
                    .setInitialDelay(Duration.between(now, next).toMillis().coerceAtLeast(1000), TimeUnit.MILLISECONDS).build())
            scheduledAt = next
        }
    }

    companion object {
        private const val WORK_NAME = "paply.task-widget-boundary"
        @Volatile private var instance: TaskWidgets? = null
        fun start(context: Context, repository: ThoughtsRepository): TaskWidgets = instance ?: synchronized(this) {
            instance ?: TaskWidgets(context.applicationContext, repository).also { instance = it }
        }
        fun get(context: Context): TaskWidgets = start(context, ThoughtsRepository.get(context))

        internal fun views(context: Context, content: TaskWidgetContent, medium: Boolean, now: Instant): RemoteViews {
            val view = RemoteViews(context.packageName, if (medium) R.layout.task_widget_medium else R.layout.task_widget_small)
            view.setTextColor(R.id.tasks_heading, C.text.toArgb())
            view.setTextColor(R.id.tasks_count, C.greenBright.toArgb())
            view.setTextViewText(R.id.tasks_count, content.openCount?.toString().orEmpty())
            view.setContentDescription(R.id.tasks_count, content.openCount?.let { "$it offene Aufgaben" }.orEmpty())
            view.setOnClickPendingIntent(R.id.tasks_root, open(context))
            view.setTextViewText(R.id.tasks_note, content.note.orEmpty())
            view.setViewVisibility(R.id.tasks_note, if (content.note != null) View.VISIBLE else View.GONE)
            val rows = listOf(R.id.tasks_row_1, R.id.tasks_row_2, R.id.tasks_row_3)
            val texts = listOf(R.id.tasks_text_1, R.id.tasks_text_2, R.id.tasks_text_3)
            val dues = listOf(R.id.tasks_due_1, R.id.tasks_due_2, R.id.tasks_due_3)
            val checks = listOf(R.id.tasks_check_1, R.id.tasks_check_2, R.id.tasks_check_3)
            val selected = content.items(medium)
            for (index in 0 until if (medium) 3 else 1) {
                val item = selected.getOrNull(index)
                view.setViewVisibility(rows[index], if (item != null) View.VISIBLE else View.GONE)
                if (item == null) continue
                view.setTextViewText(texts[index], item.text)
                view.setTextViewText(dues[index], TaskWidgetContent.due(item, now).orEmpty())
                view.setTextColor(dues[index], if (item.due(now)?.isLate == true) C.beak.toArgb() else C.thoughtPale.toArgb())
                val destination = open(context, item.thoughtID, item.taskID)
                view.setOnClickPendingIntent(texts[index], destination)
                view.setOnClickPendingIntent(dues[index], destination)
                view.setOnClickPendingIntent(rows[index], destination)
                if (medium) {
                    view.setContentDescription(checks[index], "Erledigen: ${item.text}")
                    view.setOnClickPendingIntent(checks[index], TaskWidgetActions.complete(context, item.thoughtID, item.taskID))
                }
            }
            return view
        }
        private fun open(context: Context, thoughtID: String? = null, taskID: String? = null): PendingIntent =
            PendingIntent.getActivity(context, 4100, Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                if (thoughtID != null && taskID != null) data = ReminderLinks.uri(thoughtID, taskID)
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

class TaskWidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try { TaskWidgets.get(applicationContext).update(fromWorker = true); Result.success() }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { Result.retry() }
}
