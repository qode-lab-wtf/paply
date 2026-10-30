package com.paply.android

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.content.ContextCompat
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.*
import com.paply.thoughts.ThoughtTrigger
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

object ThoughtState {
    data class State(val phase: String = "idle", val startedAt: Long = 0, val message: String = "",
        val id: String? = null, val elapsedMs: Long = 0, val level: Float = 0f, val interrupted: Boolean = false, val warnLimit: Boolean = false)
    val current = MutableStateFlow(State())
    val active get() = current.value.phase in listOf("starting", "recording", "stopping")
    fun update(context: Context, value: State) {
        val previous = current.value
        if (CaptureActivity.cardVisible && value.message.isNotBlank()) CaptureActivity.claimFeedback(value.id)
        current.value = value
        if (previous.phase != value.phase || previous.id != value.id) {
            android.service.quicksettings.TileService.requestListeningState(context, ComponentName(context, ThoughtTile::class.java))
            ThoughtWidget.updateAll(context)
        }
    }
}

class ThoughtService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var recorder: AudioCapture? = null
    private var starting = false
    private var stopping = false
    private var pendingStop: Boolean? = null
    private var captureId: String? = null
    private var lastStartId = 0
    private var nextNudge = 0L
    private var ticker: Job? = null
    private var foreground = false
    private var lastNudge = 0L
    private var discardRequested = false
    private val visibilityGuard = RecordingVisibilityGuard()
    private var lastNotificationCheck = Long.MIN_VALUE
    private val repository by lazy { ThoughtsRepository.get(this) }
    private val notifications get() = getSystemService(NotificationManager::class.java)
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate()
        scope.launch {
            SettingsRepository.get(this@ThoughtService).state.map { it.betaThoughts }.distinctUntilChanged().collect { enabled ->
                ThoughtWidget.updateAll(this@ThoughtService)
                if (!enabled && (starting || recorder != null)) finishRecording(false)
            }
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        when (intent?.action) {
            START -> if (!starting && recorder == null && !stopping) begin()
            FINISH, DISCARD -> {
                val target = intent.getStringExtra("thoughtId")
                if (target == null || target == captureId) finishRecording(intent.action == DISCARD)
                else if (recorder == null && !starting) stopSelf(startId)
            }
            REPOST -> {
                val target = intent.getStringExtra("thoughtId")
                if (recorder != null && !stopping && (target == null || target == captureId)) {
                    // Android may still return a dismissed FGS in its app-active snapshot.
                    if (!ThoughtNotifications.visible(this) ||
                        !visibilityGuard.dismissed(SystemClock.elapsedRealtime(), ::postRecordingNotification)) finishRecording(false)
                } else if (recorder == null && !starting) stopSelf(startId)
            }
            HIDDEN -> if (recorder != null && !stopping) {
                if (!ThoughtNotifications.visible(this)) finishRecording(false)
                else { nudge("leave"); nextNudge = SystemClock.elapsedRealtime() + nudgeEvery() }
            }
            else -> if (recorder == null && !starting) stopSelf(startId)
        }
        return START_NOT_STICKY
    }
    private fun begin() {
        starting = true
        val wall = System.currentTimeMillis()
        val initial = ThoughtState.State("starting", wall)
        try {
            // Complete the FGS contract immediately, even when a racing revocation/beta change rejects capture.
            if (Build.VERSION.SDK_INT >= 30) startForeground(ThoughtNotifications.RECORDING, ThoughtNotifications.recording(this, initial), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else startForeground(ThoughtNotifications.RECORDING, ThoughtNotifications.recording(this, initial))
            foreground = true
            Diag.event("thought.notification active=true count=0")
            ThoughtState.update(this, initial)
        } catch (e: Exception) { failStart(safeError(e)); return }
        scope.launch {
            var prepared: com.paply.thoughts.store.ThoughtStore.Capture? = null
            try {
                if (!SettingsRepository.get(this@ThoughtService).state.value.betaThoughts) { failStart(BETA_OFF); return@launch }
                if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) throw SecurityException("microphone")
                if (MicrophoneLease.isBusy()) throw MicrophoneBusyException()
                val captureFile = withContext(Dispatchers.IO) {
                    repository.backend().store.beginCapture(ThoughtTrigger.control, Instant.ofEpochMilli(wall)).also { prepared = it }
                }
                prepared = captureFile
                captureId = captureFile.thought.id
                if (!SettingsRepository.get(this@ThoughtService).state.value.betaThoughts || pendingStop != null) {
                    withContext(Dispatchers.IO) { captureFile.audio.close(); repository.backend().store.discardCapture(captureFile.thought.id) }
                    failStart(if (pendingStop == true) "Verworfen" else if (pendingStop == false) "Aufnahme beendet" else BETA_OFF)
                    return@launch
                }
                val capture = AudioCapture(this@ThoughtService, captureFile.audio.url.toFile(), thoughtWriter = captureFile.audio)
                capture.start(); recorder = capture; starting = false
                ThoughtState.update(this@ThoughtService, initial.copy(phase = "recording", id = captureId))
                if (runCatching { notifications.notify(ThoughtNotifications.RECORDING, ThoughtNotifications.recording(this@ThoughtService, ThoughtState.current.value)) }.isFailure) {
                    finishRecording(false); return@launch
                }
                ticker = scope.launch { tick(capture) }
                scope.launch {
                    capture.awaitEnd()
                    if (recorder === capture && !stopping) finishRecording(false)
                }
                Diag.event("thought.recording.started")
                scope.launch {
                    delay(700)
                    val posted = notifications.activeNotifications.firstOrNull { it.id == ThoughtNotifications.RECORDING && it.tag == null }
                    Diag.event("thought.notification promoted=${posted?.notification?.flags?.and(0x40000) != 0} visible=${ThoughtNotifications.visible(this@ThoughtService)}")
                }
            } catch (e: CancellationException) {
                withContext(NonCancellable + Dispatchers.IO) {
                    prepared?.let { it.audio.close(); repository.backend().store.discardCapture(it.thought.id) }
                }
                throw e
            } catch (e: Exception) {
                withContext(Dispatchers.IO) { prepared?.let { it.audio.close(); repository.backend().store.discardCapture(it.thought.id) } }
                failStart(safeError(e))
            }
        }
    }
    private suspend fun tick(capture: AudioCapture) {
        var lastInterrupted = false
        var warned = false
        while (recorder === capture && !stopping) {
            val elapsed = SystemClock.elapsedRealtime() - capture.startedAt
            val warn = elapsed >= WARN_AFTER
            val state = ThoughtState.current.value.copy(elapsedMs = elapsed, level = capture.level, interrupted = capture.interrupted, warnLimit = warn)
            ThoughtState.update(this, state)
            val now = SystemClock.elapsedRealtime()
            if (lastNotificationCheck == Long.MIN_VALUE || now - lastNotificationCheck >= 500) {
                lastNotificationCheck = now
                if (!ensureNotification()) { finishRecording(false); return }
            }
            if (state.interrupted != lastInterrupted || warn != warned) {
                if (runCatching { notifications.notify(ThoughtNotifications.RECORDING, ThoughtNotifications.recording(this, state)) }.isFailure) { finishRecording(false); return }
                lastInterrupted = state.interrupted
            }
            if (warn && !warned) { nudge("one-minute"); warned = true }
            if (!CaptureActivity.cardVisible && SystemClock.elapsedRealtime() >= nextNudge) {
                nudge("background"); nextNudge = SystemClock.elapsedRealtime() + nudgeEvery()
            }
            if (!CaptureActivity.cardVisible && !ThoughtNotifications.visible(this)) { finishRecording(false); return }
            delay(100)
        }
    }
    private fun ensureNotification(): Boolean = visibilityGuard.check(
        SystemClock.elapsedRealtime(), CaptureActivity.cardVisible,
        allowed = { ThoughtNotifications.visible(this) },
        posted = { notifications.activeNotifications.any { it.id == ThoughtNotifications.RECORDING && it.tag == null } },
        repost = ::postRecordingNotification,
    )
    private fun postRecordingNotification() {
        notifications.notify(ThoughtNotifications.RECORDING, ThoughtNotifications.recording(this, ThoughtState.current.value))
        Diag.event("thought.notification active=true count=1")
    }
    private fun nudgeEvery() = if (BuildConfig.DEBUG) CaptureDebug.nudgeEveryMs else NUDGE_EVERY
    @Suppress("DEPRECATION")
    private fun nudge(reason: String) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastNudge < 800) return
        lastNudge = now
        val vibrator = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
        // Notification usage permits the reminder in background without touching any global audio policy.
        val attributes = android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        vibrator.vibrate(VibrationEffect.createOneShot(90, VibrationEffect.DEFAULT_AMPLITUDE), attributes)
        Diag.event("thought.nudge reason=$reason")
    }
    private fun finishRecording(discard: Boolean) {
        if (starting) { if (pendingStop != true) pendingStop = discard; return }
        val capture = recorder ?: run { stopSelf(lastStartId); return }
        if (stopping) return
        discardRequested = discard
        stopping = true; ticker?.cancel()
        ThoughtState.update(this, ThoughtState.current.value.copy(phase = "stopping", level = 0f))
        capture.requestStop()
        scope.launch {
            // Commit intent before the asynchronous close/handoff can be interrupted by process death.
            if (discard) runCatching { repository.markDiscard(requireNotNull(captureId)) }
            val result = capture.awaitEnd()
            val id = requireNotNull(captureId)
            recorder = null
            // The service ends with capture. Only the application scope closes the durable handoff;
            // every network operation runs later in WorkManager, after stopSelf.
            removeForeground(); stopSelf()
            ThoughtState.update(this@ThoughtService, ThoughtState.State(id = id, message = captureEndMessage(discard, result)))
            repository.scope.launch {
                try {
                    val store = repository.backend().store
                    if (discard || result.durationMs <= 0 && result.file.length() <= 44 || !result.usable && result.error == null) {
                        repository.discardCapture(id)
                        Diag.event("thought.discard explicit=$discard fileDeleted=${!result.file.exists()}")
                        if (!discard) ThoughtNotifications.show(applicationContext, id, "Nichts gespeichert", "Keine Sprache aufgenommen")
                    } else {
                        // Any partial recording survives a read/storage failure, even below the speech threshold.
                        val duration = if (result.durationMs <= 0 && result.file.length() > 44) com.paply.thoughts.store.WAVWriter.repair(result.file.toPath()) else result.durationMs.toInt()
                        store.finishCapture(id, duration)
                        if (store.thought(id) != null) {
                            val key = runCatching { com.paply.android.settings.KeyVault(applicationContext).read() }.getOrNull()
                            val waiting = when {
                                key.isNullOrBlank() -> com.paply.thoughts.ThoughtState.waitingKey
                                !repository.online() -> com.paply.thoughts.ThoughtState.waitingNetwork
                                else -> null
                            }
                            if (waiting != null) store.update(id) { it.copy(state = waiting,
                                status = com.paply.thoughts.Thought.Status(com.paply.thoughts.processing.ThoughtProcessor.message(waiting))) }
                            ThoughtNotifications.show(applicationContext, id, if (waiting != null) "Gedanke wartet – Schlüssel/Netz prüfen" else "Gedanke gesichert",
                                if (waiting != null) "Audio bleibt bis zum Rohtext erhalten, höchstens 30 Tage." else "Wird geordnet · Mikrofon ist aus")
                            repository.kick("captured")
                        } else ThoughtNotifications.show(applicationContext, id, "Nichts gespeichert", "Keine Aufnahme vorhanden")
                    }
                    repository.publish(store)
                } catch (_: Exception) {
                    Diag.event("thought.handoff.failed")
                    ThoughtNotifications.show(applicationContext, id, "Gedanke wartet", "Teilaufnahme gesichert · Paply erneut öffnen")
                }
            }
        }
    }
    private fun removeForeground() { if (foreground) { stopForeground(STOP_FOREGROUND_REMOVE); foreground = false } }
    private fun failStart(message: String) {
        starting = false
        ThoughtState.update(this, ThoughtState.State(message = message))
        removeForeground(); stopSelf()
    }
    override fun onDestroy() {
        ticker?.cancel()
        val interruptedCapture = recorder
        val id = captureId
        recorder = null
        interruptedCapture?.requestStop()
        if (interruptedCapture != null && id != null) repository.scope.launch {
            try {
                val result = interruptedCapture.awaitEnd()
                val store = repository.backend().store
                if (discardRequested) repository.discardCapture(id) else store.finishCapture(id, result.durationMs.toInt())
                repository.publish(store); repository.kick("service-ended")
            } catch (_: Exception) {
                Diag.event("thought.handoff.failed")
                ThoughtNotifications.show(applicationContext, id, "Gedanke wartet", "Teilaufnahme gesichert · Paply erneut öffnen")
            }
        }
        scope.cancel()
        if (ThoughtState.active) ThoughtState.update(this, ThoughtState.State(id = id, message = "Aufnahme unterbrochen · Ton gesichert"))
        removeForeground()
        super.onDestroy()
    }
    companion object {
        const val START = "com.paply.android.START"
        const val FINISH = "com.paply.android.FINISH"
        const val DISCARD = "com.paply.android.DISCARD"
        const val SHOW = "com.paply.android.SHOW"
        const val TOGGLE = "com.paply.android.TOGGLE"
        const val REPOST = "com.paply.android.REPOST_RECORDING"
        const val HIDDEN = "com.paply.android.CARD_HIDDEN"
        const val BETA_OFF = "Gedanken & Aufgaben sind aus. In Paply unter Beta einschalten."
        const val WARN_AFTER = 9 * 60_000L
        const val NUDGE_EVERY = 2 * 60_000L
        fun start(context: Context): String? {
            if (!SettingsRepository.get(context).state.value.betaThoughts) return BETA_OFF
            if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return "Bitte Mikrofonzugriff erlauben."
            if (MicrophoneLease.isBusy()) return "Mikro belegt · beende zuerst die andere Aufnahme."
            return try {
                ContextCompat.startForegroundService(context, Intent(context, ThoughtService::class.java).setAction(START)); null
            } catch (e: SecurityException) { safeError(e)
            } catch (_: IllegalStateException) { "Android hat den Dienststart abgelehnt. Bitte erneut in Paply starten." }
        }
        fun command(context: Context, action: String) {
            if (ThoughtState.active) context.startService(Intent(context, ThoughtService::class.java).setAction(action)
                .putExtra("thoughtId", ThoughtState.current.value.id))
        }
    }
}
