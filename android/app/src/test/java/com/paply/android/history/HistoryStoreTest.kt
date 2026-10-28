package com.paply.android.history

import android.content.Context
import android.content.ContextWrapper
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class HistoryStoreTest {
    @get:Rule val temporary = TemporaryFolder()
    private val root: File get() = File(temporary.root, "files").apply { mkdirs() }
    private val index: File get() = File(root, "history/history.json").apply { parentFile!!.mkdirs() }
    private fun store(): HistoryStore {
        val files = root
        val context = object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir() = files
        }
        return HistoryStore(context, autoLoad = false)
    }
    private fun wav(name: String) = File(File(root, "dictations").apply { mkdirs() }, "$name.wav").apply { writeText("audio") }
    private fun row(id: String, time: Long, audio: String? = null) = JSONObject().apply {
        put("id", id); put("createdAt", time); put("audioFile", audio ?: "")
    }

    @Test fun invalidRowsAreSkippedWithoutHidingHealthyRows() = runBlocking {
        index.writeText(JSONArray().put(row("first", 1)).put("bad-row").put(JSONObject())
            .put(row("bad-status", 2).put("status", "BOGUS"))
            .put(row("negative", 3).put("durationMs", -1)).put(row("second", 4)).toString())
        val store = store(); store.reload()
        assertEquals(listOf("second", "first"), store.entries.value.map { it.id })
        store.add(HistoryEntry("third", 5))
        assertEquals(3, JSONArray(index.readText()).length())
    }
    @Test fun brokenJsonIsArchivedAndDoesNotBlockNewEntries() = runBlocking {
        val file = index.apply { writeText("broken-json") }
        val store = store(); store.reload()
        assertTrue(store.entries.value.isEmpty())
        val archive = file.parentFile!!.listFiles()!!.single { it.name.startsWith("damaged-") }
        assertEquals("broken-json", archive.readText())
        store.add(HistoryEntry("new", 1))
        assertEquals("new", JSONArray(file.readText()).getJSONObject(0).getString("id"))
    }
    @Test fun unreadableIndexIsArchivedAndRecoveryRemainsWritable() = runBlocking {
        val file = index.apply { mkdirs() } // Opening a directory as a JSON stream fails with IOException.
        val store = store(); store.reload(); store.add(HistoryEntry("new", 1))
        assertTrue(file.isFile)
        assertTrue(file.parentFile!!.listFiles()!!.any { it.name.startsWith("damaged-") })
    }
    @Test fun deletingOneEntryDeletesOnlyItsAudioAfterPersistingTheIndex() = runBlocking {
        val first = wav("first"); val second = wav("second")
        val store = store()
        store.add(HistoryEntry("first", 1, audioFile = first.path))
        store.add(HistoryEntry("second", 2, audioFile = second.path))
        store.delete(setOf("first"))
        assertFalse(first.exists()); assertTrue(second.exists())
        assertEquals("second", JSONArray(index.readText()).getJSONObject(0).getString("id"))
    }
    @Test fun deleteAllRemovesPrivateWavsButRejectsOutsideTraversalNonWavsAndSymlinks() = runBlocking {
        val privateAudio = wav("private")
        val outside = File(temporary.root, "outside.wav").apply { writeText("keep") }
        val nonWav = File(privateAudio.parentFile, "keep.json").apply { writeText("keep") }
        val symlink = File(privateAudio.parentFile, "link.wav")
        Files.createSymbolicLink(symlink.toPath(), outside.toPath())
        val store = store()
        listOf(privateAudio.path, outside.path, "${privateAudio.parent}/../../outside.wav", nonWav.path, symlink.path)
            .forEachIndexed { i, path -> store.add(HistoryEntry("$i", i.toLong(), audioFile = path)) }
        store.deleteAll()
        assertFalse(privateAudio.exists()); assertTrue(outside.exists()); assertTrue(nonWav.exists())
        assertEquals(0, JSONArray(index.readText()).length())
    }
    @Test fun symlinkedDictationsDirectoryCannotDeleteOutsideFilesDir() = runBlocking {
        val outside = File(temporary.root, "outside").apply { mkdirs() }
        val audio = File(outside, "keep.wav").apply { writeText("keep") }
        Files.createSymbolicLink(File(root, "dictations").toPath(), outside.toPath())
        val store = store(); store.add(HistoryEntry("one", 1, audioFile = audio.path)); store.deleteAll()
        assertTrue(audio.exists())
    }
    @Test fun retentionDeletesTheEvictedWavOnlyAfterTheNewIndexIsWritten() = runBlocking {
        val audio = wav("oldest")
        index.writeText(JSONArray().apply { repeat(HistoryStore.LIMIT) { put(row("$it", it.toLong(), if (it == 0) audio.path else null)) } }.toString())
        val store = store(); store.reload(); assertTrue(audio.exists())
        store.add(HistoryEntry("newest", 999))
        assertEquals(300, JSONArray(index.readText()).length())
        assertFalse(audio.exists())
        assertFalse(store.entries.value.any { it.id == "0" })
    }
    @Test fun loadingOverflowKeepsAudioUntilNextSuccessfulWrite() = runBlocking {
        val audio = wav("overflow")
        index.writeText(JSONArray().apply { repeat(301) { put(row("$it", it.toLong(), if (it == 0) audio.path else null)) } }.toString())
        val store = store(); store.reload()
        assertEquals(300, store.entries.value.size); assertTrue(audio.exists())
        store.add(HistoryEntry("newest", 999))
        assertFalse(audio.exists()); assertEquals(300, JSONArray(index.readText()).length())
    }
    @Test fun incomingEntryOlderThanTheRetentionWindowAlsoLosesItsAudio() = runBlocking {
        index.writeText(JSONArray().apply { repeat(300) { put(row("$it", it.toLong() + 1)) } }.toString())
        val audio = wav("late-old-entry"); val store = store()
        store.add(HistoryEntry("older", 0, audioFile = audio.path))
        assertFalse(audio.exists()); assertEquals(300, JSONArray(index.readText()).length())
    }
    @Test fun failedIndexWriteKeepsAudioAndPublishedEntries() = runBlocking {
        val audio = wav("keep"); val store = store()
        store.add(HistoryEntry("keep", 1, audioFile = audio.path))
        val folder = index.parentFile!!
        val moved = File(root, "history-backup")
        check(folder.renameTo(moved)); folder.writeText("blocks directory creation")
        try { store.deleteAll(); fail() } catch (_: IllegalStateException) { }
        assertTrue(audio.exists()); assertEquals("keep", store.entries.value.single().id)
        assertEquals(1, JSONArray(File(moved, "history.json").readText()).length())
    }
    @Test fun sharedAudioStaysUntilItsLastReferenceIsDeleted() = runBlocking {
        val audio = wav("shared"); val store = store()
        store.add(HistoryEntry("first", 1, audioFile = audio.path)); store.add(HistoryEntry("second", 2, audioFile = audio.path))
        store.delete(setOf("first")); assertTrue(audio.exists())
        store.delete(setOf("second")); assertFalse(audio.exists())
    }
}
