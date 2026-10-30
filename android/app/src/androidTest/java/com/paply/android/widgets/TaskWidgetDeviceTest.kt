package com.paply.android.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.BuildConfig
import com.paply.android.R
import com.paply.android.reminders.TaskReminders
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.*
import java.time.Instant
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

/** Offline fixtures and real widget PendingIntents on paply3 only. Never requires an AI key. */
class TaskWidgetDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val repository get() = ThoughtsRepository.get(context)

    @Test fun seedWidgetExamples() = runBlocking {
        check(BuildConfig.DEBUG && KeyVault(context).read() == null)
        SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
        val store = repository.backend().store
        store.purge(store.all().filter { it.id.startsWith("s_rem_") || it.id.startsWith("s_wid_") }.map { it.id })
        val now = Instant.now()
        store.save(Thought(id = "s_wid_invitation", trigger = ThoughtTrigger.app, state = ThoughtState.done,
            title = "Morgen an die Briefe denken", text = "Morgen um elf die Briefe bearbeiten. Aufgaben mit Uhrzeit können mich erinnern.",
            tasks = listOf(ThoughtTask(id = "k_wid_timed", text = "Briefe bearbeiten", dueAt = now.plusSeconds(86400), dueHasTime = true, owner = Owner.user))))
        repository.publish(store)
        TaskWidgets.get(context).update()
    }

    @Test fun completionBroadcastIsDurableAndIdempotentAndRespectsBeta() = runBlocking {
        check(BuildConfig.DEBUG && KeyVault(context).read() == null)
        val store = repository.backend().store
        val id = "s_wid_action"; val taskID = "k_wid_action"
        store.save(Thought(id = id, trigger = ThoughtTrigger.app, state = ThoughtState.done,
            tasks = listOf(ThoughtTask(id = taskID, text = "Widget-Prüfung", owner = Owner.user))))
        try {
            SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
            val action = TaskWidgetActions.complete(context, id, taskID)
            action.send()
            withTimeout(5000) { while (repository.thought(id)!!.tasks.single().doneAt == null) delay(50) }
            val once = repository.thought(id)!!.tasks.single()
            action.send(); delay(500)
            assertEquals(once, repository.thought(id)!!.tasks.single())
            assertTrue(store.thought(id)!!.tasks.single().done)
            repository.setTaskDone(id, taskID, false)
            SettingsRepository.get(context).update { it.copy(betaThoughts = false) }
            action.send(); delay(500)
            assertFalse(repository.thought(id)!!.tasks.single().done)
            SettingsRepository.get(context).update { it.copy(betaThoughts = true) }
            repository.trash(id)
            action.send(); delay(500)
            assertFalse(store.thought(id)!!.tasks.single().done)
        } finally { store.purge(listOf(id)); repository.publish(store) }
    }

    @Test fun renderedBetaAndKeyguardViewsContainNoTaskContent() = runBlocking {
        val now = Instant.now()
        val thoughts = listOf(Thought(id="s_wid_private", trigger=ThoughtTrigger.app, state=ThoughtState.done,
            tasks=listOf(ThoughtTask(id="k_wid_private", text="Privater Text", owner=Owner.user))))
        for (content in listOf(TaskWidgetContent.make(thoughts, beta=false), TaskWidgetContent.make(thoughts, beta=true, keyguard=true))) {
            instrumentation.runOnMainSync {
                val root = TaskWidgets.views(context, content, true, now).apply(context, null)
                assertEquals("", root.findViewById<TextView>(R.id.tasks_count).text.toString())
                assertEquals("", root.findViewById<TextView>(R.id.tasks_text_1).text.toString())
                assertEquals(android.view.View.GONE, root.findViewById<android.view.View>(R.id.tasks_row_1).visibility)
            }
        }
        val info = AppWidgetManager.getInstance(context).getInstalledProviders().filter {
            it.provider == ComponentName(context, TaskSmallWidget::class.java) || it.provider == ComponentName(context, TaskMediumWidget::class.java)
        }
        assertEquals(2, info.size)
        info.forEach {
            assertEquals(0, it.updatePeriodMillis)
            assertNotEquals(0, it.previewLayout)
            assertNotEquals(0, it.previewImage)
            if (android.os.Build.VERSION.SDK_INT >= 36) assertTrue(it.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_NOT_KEYGUARD != 0)
        }
    }

    /** Raster fallback for Android 10/11 pickers, rendered from the same static preview layouts. */
    @Test fun exportPickerImages() {
        check(BuildConfig.DEBUG)
        instrumentation.runOnMainSync {
            for ((name, layout, width) in listOf(Triple("small", R.layout.task_widget_preview_small, 180),
                    Triple("medium", R.layout.task_widget_preview_medium, 360))) {
                val density = context.resources.displayMetrics.density
                val view = android.view.LayoutInflater.from(context).inflate(layout, null)
                val w = (width * density).toInt(); val h = (196 * density).toInt()
                view.measure(android.view.View.MeasureSpec.makeMeasureSpec(w, android.view.View.MeasureSpec.EXACTLY),
                    android.view.View.MeasureSpec.makeMeasureSpec(h, android.view.View.MeasureSpec.EXACTLY))
                view.layout(0, 0, w, h)
                val image = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
                view.draw(android.graphics.Canvas(image))
                java.io.File(context.cacheDir, "task-widget-preview-$name.png").outputStream().use {
                    assertTrue(image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it))
                }
                image.recycle()
            }
        }
    }

    @Test fun verifyWidgetCompletionAndAlarmPlanned() = runBlocking {
        assertTrue(repository.thought("s_ui_paply")!!.tasks.first { it.id == "k_ui_guide" }.done)
        TaskReminders.get(context).reconcile()
        assertTrue(TaskReminders.get(context).state.value.plannedCount > 0)
    }
}
