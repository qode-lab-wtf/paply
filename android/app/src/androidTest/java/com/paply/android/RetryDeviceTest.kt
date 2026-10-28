package com.paply.android

import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.dictation.DictationRuntime
import com.paply.android.history.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class RetryDeviceTest {
    @Test fun missingAudioCompletesWithCurrentEntryAndPersistsTerminalReason() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val id = UUID.randomUUID().toString()
        val stale = HistoryEntry(id, 1, durationMs = 1, status = HistoryStatus.FAILED, audioFile = "/missing.wav")
        val current = stale.copy(durationMs = 9000, createdAt = 2)
        try {
            store.add(current)
            val done = CompletableDeferred<HistoryEntry>()
            var calls = 0
            DictationRuntime.retry(app, stale) { calls++; done.complete(it) }
            val result = withTimeout(5000) { done.await() }
            assertEquals(1, calls)
            assertEquals(9000L, result.durationMs)
            assertEquals(HistoryFailure.AUDIO_MISSING, result.failure)
            assertNull(result.audioFile)
            assertEquals(result, store.entries.value.first { it.id == id })
        } finally { store.delete(setOf(id)) }
    }
    @Test fun deletedAndAlreadyFinishedEntriesAlsoCompleteExactlyOnce() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val entry = HistoryEntry(UUID.randomUUID().toString(), 1, raw = "Schon fertig")
        try {
            for (exists in listOf(false, true)) {
                if (exists) store.add(entry)
                val done = CompletableDeferred<HistoryEntry>(); var calls = 0
                DictationRuntime.retry(app, entry) { calls++; done.complete(it) }
                val result = withTimeout(5000) { done.await() }
                assertEquals(1, calls)
                if (exists) assertEquals(entry, result)
                else assertEquals(HistoryFailure.AUDIO_MISSING, result.failure)
            }
        } finally { store.delete(setOf(entry.id)) }
    }
    @Test fun cancelledRetryCompletesAndReleasesBusyWithoutSendingAudio() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val entry = HistoryEntry(UUID.randomUUID().toString(), 1, status = HistoryStatus.FAILED)
        store.add(entry)
        try {
            val done = CompletableDeferred<HistoryEntry>(); var calls = 0
            withContext(Dispatchers.Main) {
                val job = DictationRuntime.retry(app, entry) { calls++; done.complete(it) }
                job.cancel()
            }
            val result = withTimeout(5000) { done.await() }
            assertEquals(1, calls)
            assertEquals(HistoryFailure.CANCELLED, result.failure)
            assertFalse(DictationRuntime.isBusy)
        } finally { store.delete(setOf(entry.id)) }
    }
    @Test fun duplicateBusyRetryCompletesWithoutChangingOrReleasingTheOwner() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val entry = HistoryEntry(UUID.randomUUID().toString(), 1, status = HistoryStatus.FAILED)
        store.add(entry); DictationRuntime.sessionStarted(entry.id)
        try {
            val done = CompletableDeferred<HistoryEntry>(); var calls = 0
            DictationRuntime.retry(app, entry) { calls++; done.complete(it) }
            assertEquals(entry, withTimeout(5000) { done.await() })
            assertEquals(1, calls); assertTrue(DictationRuntime.isBusy)
            assertEquals(entry, store.entries.value.first { it.id == entry.id })
        } finally { DictationRuntime.sessionEnded(entry.id); store.delete(setOf(entry.id)) }
    }

    @Test fun diskFullKeepsTranscribedTextAvailableAndRetainsAudioForRecovery() {
        val entry = HistoryEntry("disk-full", 1, audioFile = "/private/retained.wav")
        val result = DictationRuntime.rescueText(entry,
            com.paply.core.DictationOutcome(raw = "Gesprochen", text = "Gesprochen.", polished = "Gesprochen."),
            java.io.IOException("No space left on device"))
        assertEquals("Gesprochen.", result.text)
        assertEquals(HistoryFailure.STORAGE_FULL, result.failure)
        assertEquals(entry.audioFile, result.audioFile)
    }

}
