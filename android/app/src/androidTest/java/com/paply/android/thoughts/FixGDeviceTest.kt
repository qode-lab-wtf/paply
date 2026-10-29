package com.paply.android.thoughts

import android.app.NotificationManager
import android.content.Intent
import android.media.AudioManager
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import com.paply.android.*
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.thoughts.*
import com.paply.thoughts.processing.FileTranscriber
import com.paply.thoughts.processing.TranscriptionResult
import com.paply.thoughts.store.WAVWriter
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test

/** Offline tests on paply:5580. No test may issue a Groq request. */
class FixGDeviceTest {
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val settings get() = SettingsRepository.get(app)
    private val repo get() = ThoughtsRepository.get(app)

    @Test fun prepareOffline() = runBlocking {
        settings.update { it.copy(betaThoughts = false, mainLanguage = "de", automaticLanguages = false, manualLanguages = listOf("de")) }
        KeyVault(app).remove()
        repo.backend()
        Unit
    }
    @Test fun concurrentPublicationsRemainConsistent() = runBlocking {
        check(KeyVault(app).read() == null)
        settings.update { it.copy(betaThoughts = false) }
        val store = repo.backend().store
        val id = "s_fixg_publish"
        try {
            store.save(Thought(id = id, trigger = ThoughtTrigger.app, state = com.paply.thoughts.ThoughtState.done))
            coroutineScope {
                repeat(40) { version -> launch(Dispatchers.IO) {
                    store.update(id) { it.copy(title = "Version $version", tasks = listOf(ThoughtTask(text = "Version $version", owner = Owner.user))) }
                    repo.publish(store)
                } }
            }
            repo.publish(store)
            val published = repo.thoughts.value.single { it.id == id }
            assertEquals(store.thought(id), published)
            assertEquals(published, repo.tasks.value.single { it.thought.id == id }.thought)
            assertEquals(ThoughtsRepository.Phase.PROCESSED, repo.status.value[id]!!.phase)
        } finally { store.purge(id); repo.publish(store) }
    }
    @Test fun betaOffRetainsWaitingAudioAndSkipsHousekeepingThenOnResumes() = runBlocking {
        check(KeyVault(app).read() == null)
        settings.update { it.copy(betaThoughts = false) }
        val store = repo.backend().store
        val capture = store.beginCapture(ThoughtTrigger.app, Instant.now().minusSeconds(31L * 86400))
        capture.audio.append(FloatArray(16000)); val duration = capture.audio.close()
        store.finishCapture(capture.thought.id, duration)
        try {
            repo.kick("fixg-off"); repo.maintenance(); delay(700)
            assertTrue(capture.audio.url.toFile().exists())
            assertEquals(com.paply.thoughts.ThoughtState.captured, store.thought(capture.thought.id)!!.state)
            val jobs = WorkManager.getInstance(app).getWorkInfosForUniqueWork("paply-thoughts").get()
            assertTrue(jobs.all { it.state.isFinished })
            // Age the fixture back before resuming, so the processor exercises waitingKey.
            store.update(capture.thought.id) { it.copy(createdAt = Instant.now()) }
            settings.update { it.copy(betaThoughts = true) }
            withTimeout(12000) { while (store.thought(capture.thought.id)?.state != com.paply.thoughts.ThoughtState.waitingKey) delay(100) }
            assertTrue(capture.audio.url.toFile().exists())
        } finally { settings.update { it.copy(betaThoughts = false) }; store.purge(capture.thought.id); repo.publish(store) }
    }
    @Test fun waitingKeyDoesNotScheduleWakeAlarm() = runBlocking {
        check(KeyVault(app).read() == null)
        settings.update { it.copy(betaThoughts = false) }
        val wm = WorkManager.getInstance(app)
        wm.cancelUniqueWork("paply-thoughts-retry").result.get()
        val store = repo.backend().store
        val id = "s_fixg_waiting"
        store.save(Thought(id = id, trigger = ThoughtTrigger.app, state = com.paply.thoughts.ThoughtState.waitingKey))
        try {
            settings.update { it.copy(betaThoughts = true) }
            repo.kick("fixg-key-test")
            delay(2000)
            assertTrue(wm.getWorkInfosForUniqueWork("paply-thoughts-retry").get().all { it.state.isFinished })
            assertNotNull(store.thought(id))
        } finally { settings.update { it.copy(betaThoughts = false) }; store.purge(id); repo.publish(store) }
    }
    @Test fun tenMinuteSilentFileUsesBoundedMemoryAndNoNetwork() = runBlocking {
        val file = File(app.cacheDir, "fixg-ten-minutes.wav")
        try {
            WAVWriter(file.toPath()).also { writer -> repeat(600) { writer.append(FloatArray(16000)) }; writer.close() }
            assertEquals(TranscriptionResult.NoSpeech,
                FileTranscriber().transcribe(file.toPath(), "unused", com.paply.core.PaplySettings()))
        } finally { file.delete() }
    }
    @Test fun ringingModeAloneDoesNotDiscardAudio() = runBlocking {
        val audio = app.getSystemService(AudioManager::class.java)
        val previous = audio.mode
        val file = File(app.cacheDir, "fixg-ringing.wav")
        var capture: AudioCapture? = null
        try {
            audio.mode = AudioManager.MODE_RINGTONE
            assertFalse(audio.isMicrophoneMute)
            capture = AudioCapture(app, file, maxMs = 1200)
            capture.start()
            val result = withTimeout(6000) { capture.awaitEnd() }
            assertFalse(result.silenced)
            assertTrue(result.durationMs > 500)
            assertFalse(MicrophoneLease.isBusy())
        } finally { capture?.finish(); audio.mode = previous; file.delete() }
    }
    @Test fun foregroundExistsBeforeRecordingStateAndDismissalReposts() = runBlocking {
        check(KeyVault(app).read() == null)
        settings.update { it.copy(betaThoughts = true) }
        val foregroundAtPublication = async(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            com.paply.android.ThoughtState.current.first { it.phase == "starting" }
            @Suppress("DEPRECATION")
            app.getSystemService(android.app.ActivityManager::class.java).getRunningServices(100)
                .any { it.service.className == ThoughtService::class.java.name && it.foreground }
        }
        app.startActivity(Intent(app, CaptureActivity::class.java).setAction(ThoughtService.START).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            assertTrue(withTimeout(7000) { foregroundAtPublication.await() })
            withTimeout(7000) { com.paply.android.ThoughtState.current.first { it.phase == "recording" } }
            val manager = app.getSystemService(NotificationManager::class.java)
            withTimeout(3000) { while (manager.activeNotifications.none { it.id == ThoughtNotifications.RECORDING && it.tag == null }) delay(20) }
            val initial = manager.activeNotifications.single { it.id == ThoughtNotifications.RECORDING && it.tag == null }
            assertTrue(initial.notification.actions.single { it.title == "Verwerfen" }.isAuthenticationRequired)
            manager.cancel(ThoughtNotifications.RECORDING)
            // Exercise the same deleteIntent dispatched by the notification shade.
            initial.notification.deleteIntent.send()
            withTimeout(2000) { while (manager.activeNotifications.none {
                it.id == ThoughtNotifications.RECORDING && it.tag == null && it.postTime > initial.postTime
            }) delay(20) }
            assertTrue(com.paply.android.ThoughtState.active)
        } finally {
            foregroundAtPublication.cancel()
            ThoughtService.command(app, ThoughtService.DISCARD)
            withTimeout(5000) { while (MicrophoneLease.isBusy()) delay(20) }
            settings.update { it.copy(betaThoughts = false) }
        }
    }
    @Test fun enableBetaForManualCapture() = runBlocking {
        settings.update { it.copy(betaThoughts = true, mainLanguage = "de", automaticLanguages = false, manualLanguages = listOf("de")) }
    }
    @Test fun disableBetaForManualCapture() = runBlocking { settings.update { it.copy(betaThoughts = false) } }
}
