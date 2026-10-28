package com.paply.android.thoughts

import androidx.test.platform.app.InstrumentationRegistry
import com.paply.core.PaplySettings
import com.paply.thoughts.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.local.CandidateFinder
import com.paply.thoughts.local.TopicIndex
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.ThoughtStore
import com.paply.thoughts.store.WAVWriter
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Real Android filesystem/ICU, deterministic offline adapters; never consumes Groq quota. */
class ThoughtStorageDeviceTest {
    private fun directory() = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
        "thought-test-${UUID.randomUUID()}").apply { mkdirs() }
    private fun source(text: String = "Morgen muss ich die Tomaten im Garten gießen.") = ThoughtSource(text,
        PartSplitter.sentences(text, "fixture"), "fixture", Instant.now(), listOf("de"), 1.0)

    @Test fun androidDurableSourceReleasesAudioAndSurvivesReload() {
        val root = directory()
        try {
            val store = ThoughtStore(root.toPath())
            val capture = store.beginCapture(ThoughtTrigger.app, Instant.now())
            capture.audio.append(FloatArray(16000) { .1f })
            val duration = capture.audio.close()
            store.finishCapture(capture.thought.id, duration)
            val audio = store.audioURL(capture.thought.id)!!
            store.saveSourceOnce(capture.thought.id, source())
            assertFalse(Files.exists(audio))
            val reloaded = ThoughtStore(root.toPath())
            assertEquals(source().text, reloaded.source(capture.thought.id)?.text)
            assertNull(reloaded.thought(capture.thought.id)?.audio)
        } finally { root.deleteRecursively() }
    }

    @Test fun processDeathRecoversPartialWavWithoutStartingMicrophone() {
        val root = directory()
        try {
            val store = ThoughtStore(root.toPath())
            val capture = store.beginCapture(ThoughtTrigger.control, Instant.now())
            capture.audio.append(FloatArray(8000) { .2f }); capture.audio.close()
            // The process died before finishCapture: metadata still says recording.
            val reopened = ThoughtStore(root.toPath())
            assertEquals(listOf(capture.thought.id), reopened.recover())
            val thought = reopened.thought(capture.thought.id)!!
            assertEquals(ThoughtState.captured, thought.state)
            assertEquals(500, thought.durationMs)
            assertEquals(8000, FileTranscriber.readSamples(reopened.audioURL(thought.id)!!)!!.size)
            assertFalse(com.paply.android.MicrophoneLease.isBusy())
        } finally { root.deleteRecursively() }
    }

    @Test fun processDeathAfterDiscardNeverRecoversAudioForProcessing() {
        val root = directory()
        try {
            val store = ThoughtStore(root.toPath())
            val capture = store.beginCapture(ThoughtTrigger.control, Instant.now())
            capture.audio.append(FloatArray(8000) { .2f }); capture.audio.close()
            CaptureDiscardJournal.mark(root, capture.thought.id)
            val reopened = ThoughtStore(root.toPath())
            CaptureDiscardJournal.recover(root, reopened)
            assertTrue(reopened.recover().isEmpty())
            assertTrue(reopened.all().isEmpty())
            assertFalse(capture.audio.url.toFile().exists())
            CaptureDiscardJournal.recover(root, reopened)
        } finally { root.deleteRecursively() }
    }

    @Test fun migrationIsRestartableAndDoesNotRecreateDeletedLegacyThought() {
        val root = directory()
        try {
            val name = UUID.randomUUID().toString()
            val id = "p0_" + name.replace("-", "")
            val text = "Die Tomaten brauchen morgen Wasser."
            val old = File(root, "$name.json")
            old.writeText(JSONObject().put("text", text).put("createdAt", 123456789L).put("durationMs", 1000).toString())
            val audio = File(root, "$name.wav")
            WAVWriter(audio.toPath()).also { it.append(FloatArray(16000) { .1f }); it.close() }
            val store = ThoughtStore(root.toPath())
            // Simulate a crash after the new durable source, before legacy unlink.
            store.save(Thought(id = id, trigger = ThoughtTrigger.unknown, state = ThoughtState.captured))
            store.saveSourceOnce(id, source(text))
            assertEquals(1, LegacyThoughtMigration.run(root, store))
            assertEquals(0, LegacyThoughtMigration.run(root, store))
            assertEquals(1, store.all().size)
            assertEquals(text, store.source(id)?.text)
            assertFalse(audio.exists()); assertFalse(old.exists())
            store.purge(id)
            LegacyThoughtMigration.run(root, store)
            assertTrue(store.all().isEmpty())
        } finally { root.deleteRecursively() }
    }

    @Test fun migrationRepairsPhaseZeroHeaderAndKeepsEverySample() {
        val root = directory()
        try {
            val name = UUID.randomUUID().toString()
            val old = File(root, "$name.wav")
            old.writeBytes(ByteArray(44) + ByteArray(16000) { 12 })
            val store = ThoughtStore(root.toPath())
            assertEquals(1, LegacyThoughtMigration.run(root, store))
            val t = store.all().single()
            assertEquals(500, t.durationMs)
            assertEquals(8000, FileTranscriber.readSamples(store.audioURL(t.id)!!)!!.size)
            assertFalse(old.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun leftoverLegacyFileDoesNotReprocessAnAlreadyCompletedThought() {
        val root = directory()
        try {
            val name = UUID.randomUUID().toString()
            val legacy = File(root, "$name.json")
            val contents = JSONObject().put("text", "Garten gießen").put("createdAt", 123456L).toString()
            legacy.writeText(contents)
            val store = ThoughtStore(root.toPath())
            LegacyThoughtMigration.run(root, store)
            val id = store.all().single().id
            store.update(id) { it.copy(state = ThoughtState.done, title = "Mein Titel", titleOwner = Owner.user) }
            // The original could survive if a prior unlink failed; replay must preserve this result.
            legacy.writeText(contents)
            LegacyThoughtMigration.run(root, store)
            assertEquals(ThoughtState.done, store.thought(id)?.state)
            assertEquals("Mein Titel", store.thought(id)?.title)
            assertFalse(legacy.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun corruptLegacyFileDoesNotBlockGoodRecordsOrDestroyOriginalBytes() {
        val root = directory()
        try {
            val bad = File(root, "${UUID.randomUUID()}.json").apply { writeText("{damaged") }
            val good = File(root, "${UUID.randomUUID()}.json").apply {
                writeText(JSONObject().put("text", "Garten gießen").put("createdAt", 123456L).toString())
            }
            val store = ThoughtStore(root.toPath())
            assertEquals(1, LegacyThoughtMigration.run(root, store))
            assertEquals("{damaged", bad.readText())
            assertFalse(good.exists())
            assertEquals("Garten gießen", store.source(store.all().single().id)?.text)
        } finally { root.deleteRecursively() }
    }

    @Test fun dictationBlocksCallsAndUserEditsWinDuringAICommit() = runBlocking {
        val root = directory()
        var processor: ThoughtProcessor? = null
        try {
            val store = ThoughtStore(root.toPath())
            val t = Thought(trigger = ThoughtTrigger.app, state = ThoughtState.transcribed)
            store.save(t); store.saveSourceOnce(t.id, source())
            val userTopic = Topic(title = "Mein Garten", icon = TopicIcon.leaf, owner = Owner.user)
            store.saveTopics(listOf(userTopic))
            val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val busy = java.util.concurrent.atomic.AtomicBoolean(true)
            var calls = 0
            val structurer = ThoughtStructuring { _, _ ->
                calls++; entered.complete(Unit); release.await()
                StructureOutcome.Success(StructureResult("KI-Titel", "KI-Text", TopicDecision.New("Garten", TopicIcon.leaf),
                    emptyList(), emptyList()), "fixture", TokenUsage(1, 1, 2))
            }
            val finder = CandidateFinder(store)
            processor = ThoughtProcessor(store, structurer, finder, TokenLedger(root.toPath().resolve("ledger.json")),
                ProcessorEnvironment({ "fixture-key" }, { true }, { busy.get() }, { PaplySettings() }, "de"),
                TopicIndex, finder, options = ThoughtProcessor.Options(autoRetry = false, dictationPoll = .02))
            processor.kick("test")
            delay(150); assertEquals(0, calls)
            busy.set(false); withTimeout(4000) { entered.await() }
            store.update(t.id) { it.copy(title = "Mein Titel", titleOwner = Owner.user, text = "Meine Worte", textOwner = Owner.user,
                topicId = userTopic.id, topicOwner = Owner.user) }
            release.complete(Unit); withTimeout(4000) { processor.waitUntilIdle() }
            val saved = store.thought(t.id)!!
            assertEquals(ThoughtState.done, saved.state)
            assertEquals("Mein Titel", saved.title); assertEquals("Meine Worte", saved.text); assertEquals(userTopic.id, saved.topicId)
            assertEquals(1, store.topics().size)
        } finally { processor?.close(); root.deleteRecursively() }
    }
}
