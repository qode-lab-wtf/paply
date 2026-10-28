package com.paply.android

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

object ThoughtState {
    data class State(val phase: String = "idle", val startedAt: Long = 0, val message: String = "")
    val current = MutableStateFlow(State())
    val active get() = current.value.phase in listOf("starting", "recording", "processing")
    fun update(context: Context, value: State) {
        current.value = value
        android.service.quicksettings.TileService.requestListeningState(context, ComponentName(context, ThoughtTile::class.java))
    }
}

class ThoughtService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var recorder: AudioCapture? = null
    private var working = false
    private val notifications get() = getSystemService(NotificationManager::class.java)
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when(intent?.action) {
            START -> if (!working) begin()
            FINISH -> finishRecording(false)
            DISCARD -> finishRecording(true)
        }
        return START_NOT_STICKY
    }
    private fun begin() {
        working = true
        val wall = System.currentTimeMillis()
        ThoughtState.update(this, ThoughtState.State("starting", wall))
        try {
            notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Gedankenaufnahme", NotificationManager.IMPORTANCE_DEFAULT))
            if (Build.VERSION.SDK_INT >= 30) startForeground(NOTIFICATION, notification(wall, false), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else startForeground(NOTIFICATION, notification(wall, false))
            val capture = AudioCapture(this, ThoughtStore(this).newAudio())
            capture.start(); recorder = capture
            ThoughtState.update(this, ThoughtState.State("recording", wall))
            scope.launch {
                val result = capture.awaitEnd()
                if (recorder === capture && ThoughtState.current.value.phase == "recording") finishRecording(result.error != null)
            }
            // The system marks actual promotion after posting, not on the original builder object.
            scope.launch {
                delay(700)
                val flags = notifications.activeNotifications.firstOrNull { it.id == NOTIFICATION }?.notification?.flags ?: 0
                val allowed = if (Build.VERSION.SDK_INT >= 37) notifications.canPostPromotedNotifications() else null
                Diag.event("thought.notification flags=$flags promoted=${flags and 0x40000 != 0} allowed=$allowed")
            }
        } catch (e: Exception) {
            Diag.event("thought.start.failed type=${e.javaClass.simpleName}")
            end(safeError(e))
        }
    }
    private fun finishRecording(discard: Boolean) {
        val capture = recorder ?: return
        if (ThoughtState.current.value.phase != "recording") return
        ThoughtState.update(this, ThoughtState.current.value.copy(phase = "processing"))
        capture.requestStop()
        scope.launch {
            try {
                val result = capture.finish(); recorder = null
                if (discard || !result.usable) {
                    withContext(Dispatchers.IO) { capture.file.delete() }
                    Diag.event("thought.discard explicit=$discard fileDeleted=${!capture.file.exists()}")
                    end(if (discard) "Verworfen" else "Keine hörbare Sprache aufgenommen."); return@launch
                }
                withContext(Dispatchers.IO) { ThoughtStore(this@ThoughtService).markReady(result) }
                notifications.notify(NOTIFICATION, notification(ThoughtState.current.value.startedAt, true))
                val key = withContext(Dispatchers.IO) { com.paply.android.settings.KeyVault(this@ThoughtService).read().orEmpty() }
                val raw = com.paply.core.GroqClient(key, diagnostic = Diag::event).transcribe(result.file, result.durationMs / 1000.0)
                if (raw.text.isBlank()) { end("Nichts verstanden. Aufnahme für Neuversuch behalten."); return@launch }
                withContext(Dispatchers.IO) { ThoughtStore(this@ThoughtService).save(result.file, raw.text, result.durationMs) }
                end("Gedanke gespeichert")
            } catch (e: CancellationException) { throw e
            } catch (e: Exception) {
                Diag.event("thought.process.failed type=${e.javaClass.simpleName}")
                end(safeError(e) + " Aufnahme für Neuversuch behalten.")
            }
        }
    }
    private fun end(message: String) {
        working = false
        ThoughtState.update(this, ThoughtState.State(message = message))
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    private fun notification(start: Long, processing: Boolean): Notification {
        val content = PendingIntent.getActivity(this, 0, Intent(this, CaptureActivity::class.java).setAction(SHOW), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(com.paply.android.R.drawable.ic_mic)
            .setContentTitle(if (processing) "Paply schreibt den Gedanken …" else "Paply hört zu")
            .setContentText(if (processing) "Mikrofon ist aus" else "Gedankenaufnahme · maximal 10 Minuten")
            .setOngoing(true).setWhen(start).setUsesChronometer(!processing).setShowWhen(true)
            .setOnlyAlertOnce(true).setContentIntent(content).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(!processing)
        if (!processing) {
            builder.addAction(0, "Fertig", action(FINISH, 1))
            builder.addAction(0, "Verwerfen", action(DISCARD, 2))
        }
        return builder.build()
    }
    private fun action(action: String, code: Int) = PendingIntent.getService(this, code,
        Intent(this, ThoughtService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    override fun onDestroy() {
        recorder?.requestStop(); recorder = null
        scope.cancel()
        if (ThoughtState.active) ThoughtState.update(this, ThoughtState.State(message = "Aufnahme unterbrochen"))
        super.onDestroy()
    }
    companion object {
        const val START = "com.paply.android.START"
        const val FINISH = "com.paply.android.FINISH"
        const val DISCARD = "com.paply.android.DISCARD"
        const val SHOW = "com.paply.android.SHOW"
        private const val CHANNEL = "paply-recording"
        private const val NOTIFICATION = 1
        /** Called immediately from a resumed Activity or, debug-only, TileService.onClick. */
        fun start(context: Context): String? {
            return try {
                ContextCompat.startForegroundService(context, Intent(context, ThoughtService::class.java).setAction(START)); null
            } catch (e: SecurityException) {
                Diag.event("thought.launch.failed type=SecurityException"); safeError(e)
            } catch (e: RuntimeException) {
                if (Build.VERSION.SDK_INT >= 31 && e is ForegroundServiceStartNotAllowedException) {
                    Diag.event("thought.launch.failed type=ForegroundServiceStartNotAllowedException")
                    "Android hat den Dienststart im Hintergrund abgelehnt."
                } else throw e
            }
        }
        fun command(context: Context, action: String) {
            if (ThoughtState.active) context.startService(Intent(context, ThoughtService::class.java).setAction(action))
        }
    }
}
