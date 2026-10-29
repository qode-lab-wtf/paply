package com.paply.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.paply.android.settings.SettingsRepository

/** Text-free Home entry point; start and finish always open the visible capture card. */
class ThoughtWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = update(context, manager, ids)
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            update(context, manager, manager.getAppWidgetIds(ComponentName(context, ThoughtWidget::class.java)))
        }
        internal fun captureIntent(context: Context, id: Int): PendingIntent {
            val intent = Intent(context, CaptureActivity::class.java).setAction(ThoughtService.TOGGLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, 100 + id, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val state = ThoughtState.current.value
            val enabled = SettingsRepository.get(context).state.value.betaThoughts
            val active = ThoughtState.active
            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.thought_widget)
                views.setTextViewText(R.id.widget_status, if (active) "Nochmal tippen: fertig" else if (enabled) "Tippen und sprechen" else "In Paply unter Beta einschalten")
                views.setViewVisibility(R.id.widget_timer, if (active) View.VISIBLE else View.GONE)
                views.setChronometer(R.id.widget_timer, SystemClock.elapsedRealtime() - (System.currentTimeMillis() - state.startedAt), null, active)
                views.setOnClickPendingIntent(R.id.widget_root, captureIntent(context, id))
                manager.updateAppWidget(id, views)
            }
        }
    }
}
