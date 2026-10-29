package com.paply.android.thoughts

import android.app.*
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.paply.android.*
import com.paply.thoughts.ProcessorEvent

object ThoughtNotifications {
    const val RECORDING = 1
    const val CHANNEL = "paply-thought-recording-v2"
    private const val RESULTS = "paply-thought-results"
    fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(listOf(
            NotificationChannel(CHANNEL, "Gedankenaufnahme", NotificationManager.IMPORTANCE_LOW),
            NotificationChannel(RESULTS, "Gespeicherte Gedanken", NotificationManager.IMPORTANCE_LOW),
        ).onEach { it.setSound(null, null); it.enableVibration(false); it.setShowBadge(false) })
    }
    private val visibility = VisibilityCache()
    fun visible(context: Context): Boolean = visibility.get(android.os.SystemClock.elapsedRealtime()) {
        NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }
    internal fun invalidateVisibility() = visibility.invalidate()
    fun recording(context: Context, state: ThoughtState.State): Notification {
        channels(context)
        val content = PendingIntent.getActivity(context, 0, Intent(context, CaptureActivity::class.java).setAction(ThoughtService.SHOW)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT)
        val text = if (state.warnLimit) "Gedanke · noch 1 Min." else if (state.interrupted) "Bisheriger Ton gesichert · danach geht es weiter" else "Gedankenaufnahme · maximal 10 Minuten"
        return NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_mic)
            .setContentTitle(if (state.interrupted) "Unterbrochen" else "Paply hört zu")
            .setContentText(text).setWhen(state.startedAt).setUsesChronometer(true).setShowWhen(true)
            .setOngoing(true).setOnlyAlertOnce(true).setContentIntent(content)
            .setDeleteIntent(action(context, state.id, ThoughtService.REPOST, 4)).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS).setRequestPromotedOngoing(true)
            .addAction(0, "Fertig", action(context, state.id, ThoughtService.FINISH, 1))
            .addAction(NotificationCompat.Action.Builder(0, "Verwerfen", action(context, state.id, ThoughtService.DISCARD, 2))
                .setAuthenticationRequired(true).build()).build()
    }
    private fun action(context: Context, id: String?, action: String, code: Int) = PendingIntent.getService(context, code,
        Intent(context, ThoughtService::class.java).setAction(action).putExtra("thoughtId", id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    fun processing(context: Context): Notification {
        channels(context)
        return NotificationCompat.Builder(context, RESULTS).setSmallIcon(R.drawable.ic_stat_paply)
            .setContentTitle("Paply ordnet Gedanken").setContentText("Mikrofon ist aus")
            .setOngoing(true).setOnlyAlertOnce(true).build()
    }
    fun result(context: Context, event: ProcessorEvent) {
        when (event) {
            is ProcessorEvent.Saved -> show(context, event.id, "Gedanke gespeichert", "In Paply ansehen")
            is ProcessorEvent.Waiting -> show(context, event.id, "Gedanke wartet – Schlüssel/Netz prüfen", event.message)
            is ProcessorEvent.Failed -> show(context, event.id, "Gedanke wartet", event.message)
            is ProcessorEvent.Empty -> show(context, event.id, "Nichts verstanden", "Keine Sprache gespeichert")
            is ProcessorEvent.Processing -> Unit
        }
    }
    fun show(context: Context, id: String, title: String, message: String) {
        channels(context)
        val intent = Intent(context, MainActivity::class.java).putExtra("thoughtId", id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val content = PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, RESULTS).setSmallIcon(R.drawable.ic_stat_paply)
            .setContentTitle(title).setContentText(message).setContentIntent(content).setAutoCancel(true)
            .setOnlyAlertOnce(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) runCatching { context.getSystemService(NotificationManager::class.java).notify(id, 2, notification) }
        if (!ThoughtState.active && ThoughtState.current.value.id == id) {
            ThoughtState.update(context, ThoughtState.State(id = id, message = title))
        }
    }
}
