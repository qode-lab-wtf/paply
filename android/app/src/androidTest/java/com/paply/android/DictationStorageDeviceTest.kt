package com.paply.android

import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.dictation.DictationRuntime
import com.paply.android.history.*
import com.paply.core.DictationOutcome
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class DictationStorageDeviceTest {
    @Test fun failureRetainsAudioAndSuccessRemovesItAfterDurableText() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val dir = File(app.filesDir, "dictations").apply { mkdirs() }
        val file = File(dir, "test-${UUID.randomUUID()}.wav").apply { writeBytes(byteArrayOf(1, 2)) }
        val entry = HistoryEntry(UUID.randomUUID().toString(), System.currentTimeMillis(),
            status = HistoryStatus.PENDING, audioFile = file.path)
        try {
            store.add(entry)
            val failed = DictationRuntime.persist(app, entry, DictationOutcome(errorMessage = "Offline"))
            assertEquals(HistoryStatus.FAILED, failed.status)
            assertTrue(file.exists())
            val saved = DictationRuntime.persist(app, failed, DictationOutcome(text = "Hallo.", raw = "Hallo."), HistoryStatus.OK)
            assertEquals(HistoryStatus.OK, saved.status)
            assertNull(saved.audioFile)
            assertFalse(file.exists())
            assertEquals("Hallo.", store.entries.value.first { it.id == entry.id }.text)
            assertTrue(File(app.filesDir, "history/history.json").readText().contains("Hallo."))
        } finally { store.delete(setOf(entry.id)); file.delete() }
    }

    @Test fun deletedEntryCannotBeResurrectedByAsyncCompletion() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val store = HistoryStore.get(app)
        val file = File(File(app.filesDir, "dictations").apply { mkdirs() }, "test-${UUID.randomUUID()}.wav")
        file.writeBytes(byteArrayOf(1))
        val entry = HistoryEntry(UUID.randomUUID().toString(), System.currentTimeMillis(), audioFile = file.path)
        try {
            store.add(entry); store.delete(setOf(entry.id))
            assertFalse(store.updateIfPresent(entry))
            try {
                DictationRuntime.persist(app, entry, DictationOutcome(text = "Hallo.", raw = "Hallo."))
                fail("Completion must respect deletion")
            } catch (_: CancellationException) { }
            assertFalse(store.entries.value.any { it.id == entry.id })
            assertFalse(file.exists())
        } finally { store.delete(setOf(entry.id)); file.delete() }
    }
}
