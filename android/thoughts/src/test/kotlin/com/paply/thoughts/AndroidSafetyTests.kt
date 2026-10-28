package com.paply.thoughts

import com.paply.thoughts.ai.*
import com.paply.thoughts.model.*
import com.paply.thoughts.nlp.*
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.*
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

class AndroidSafetyTests {
    @Test
    fun corruptAuxiliaryFilesArePreservedWithoutBlockingOtherThoughts() {
        val root = StoreSupport.temporaryRoot()
        try {
            val store = ThoughtStore(root)
            val a = StoreSupport.thought()
            val b = StoreSupport.thought()
            store.save(a)
            store.save(b)
            val broken = "{not valid json"
            val files =
                listOf(
                    store.sourceURL(a.id),
                    store.aiResultURL(a.id),
                    store.aiPartsURL(a.id),
                    store.suggestionsURL,
                )
            files.forEach { Files.writeString(it, broken) }
            assertNull(store.source(a.id))
            assertNull(store.aiResultRecord(a.id))
            assertNull(store.parts(a.id))
            assertTrue(store.pendingSuggestions().isEmpty())
            assertNotNull(store.thought(b.id))
            val damaged =
                Files.walk(root).use { paths ->
                    paths.filter { it.fileName.toString().startsWith("damaged-") }.toList()
                }
            assertEquals(4, damaged.size)
            assertTrue(damaged.all { Files.readString(it) == broken })
        } finally {
            StoreSupport.remove(root)
        }
    }

    @Test
    fun callerCollectionsCannotMutatePersistedSnapshots() {
        Harness().use { h ->
            val languages = mutableListOf("de", "en")
            val tasks =
                mutableListOf(
                    ThoughtTask(text = "Original", owner = Owner.user),
                    ThoughtTask(text = "Zweite", owner = Owner.user),
                )
            val t = StoreSupport.thought(languages = languages).copy(tasks = tasks)
            h.store.save(t)
            languages.clear()
            tasks.clear()
            assertEquals(listOf("de", "en"), h.store.thought(t.id)?.languages)
            assertEquals(2, h.store.thought(t.id)?.tasks?.size)
            (h.store.thought(t.id)!!.tasks as MutableList).clear()
            assertEquals(2, h.store.thought(t.id)?.tasks?.size)
            val read = h.store.all().first()
            (read.languages as MutableList).clear()
            assertEquals(2, h.store.thought(t.id)?.languages?.size)
        }
    }

    @Test
    fun userEditsDuringTheAIRequestWinAtCommit() = runBlocking {
        Harness().use { h ->
            val own =
                Topic(
                    title = "Eigenes",
                    icon = TopicIcon.book,
                    owner = Owner.user,
                    note = "Eigene Beschreibung",
                )
            h.store.saveTopics(listOf(own))
            val id = h.capture()
            h.structurer.onCall = {
                h.store.update(id) { t ->
                    t.copy(
                        title = "Eigener Titel",
                        titleOwner = Owner.user,
                        text = "Eigener Text",
                        textOwner = Owner.user,
                        topicId = own.id,
                        topicOwner = Owner.user,
                        tasks = listOf(ThoughtTask(text = "Tomaten gießen", owner = Owner.user)),
                        links =
                            listOf(ThoughtLink("s_own", LinkKind.continues, "Eigen", Owner.user)),
                    )
                }
            }
            h.run()
            val t = h.thought(id)!!
            assertEquals("Eigener Titel", t.title)
            assertEquals("Eigener Text", t.text)
            assertEquals(own.id, t.topicId)
            assertEquals(Owner.user, t.tasks.single().owner)
            assertEquals("s_own", t.links.single().target)
            assertEquals(listOf(own), h.store.topics())
        }
    }

    @Test
    fun aBurstOfKicksNeverDuplicatesAnUpload() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            val started = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            h.transcriber.onCall = {
                started.complete(Unit)
                release.await()
            }
            h.processor.kick("first")
            withTimeout(2000) { started.await() }
            coroutineScope {
                repeat(20) { launch(Dispatchers.Default) { h.processor.kick("burst") } }
            }
            release.complete(Unit)
            withTimeout(2000) { h.processor.waitUntilIdle() }
            assertEquals(1, h.transcriber.calls)
            assertEquals(1, h.structurer.calls)
            assertEquals(ThoughtState.done, h.thought(id)?.state)
        }
    }

    @Test
    fun cancellationLeavesThePersistedSourceResumable() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            val started = CompletableDeferred<Unit>()
            h.structurer.onCall = {
                started.complete(Unit)
                awaitCancellation()
            }
            h.processor.kick("first")
            withTimeout(2000) { started.await() }
            h.processor.cancelRunning()
            h.processor.waitUntilIdle()
            assertNotNull(h.store.source(id))
            assertNull(h.store.audioURL(id))
            h.structurer.onCall = {}
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(1, h.transcriber.calls)
        }
    }

    @Test
    fun serverStringsCannotInjectThoughtTextIntoTrace() = runBlocking {
        val r = TraceRecorder()
        MockWebServer().use { s ->
            s.enqueue(mockError(400, "PRIVATE-THOUGHT"))
            val o =
                ThoughtStructurer(baseURL = s.url("/"), trace = r.trace)
                    .structure(AIFixture.input(), "test-placeholder")
            assertEquals(StructureOutcome.Unusable("request_rejected"), o)
            r.assertNoContent(listOf("PRIVATE-THOUGHT"))
        }
    }

    @Test
    fun snowballIsExplicitAndEmbeddingsStayUnavailable() {
        val de = SnowballLemmatizer("de")
        val en = SnowballLemmatizer("en")
        assertEquals("haus", de.stem("häuser", "de"))
        assertEquals("run", en.stem("running", "en"))
        val tokens = de.analyze("Heute besucht iPhone Müller in Berlin.", "de")
        assertTrue(tokens.first { it.original == "Müller" }.isName)
        assertEquals(
            LexicalAnalyzer.PartOfSpeech.noun,
            tokens.first { it.original == "Berlin" }.partOfSpeech,
        )
        assertFalse(UnavailableEmbedder.available)
        assertNull(UnavailableEmbedder.embed("Garten", "de"))
    }

    @Test
    fun unsupportedAndAmbiguousDeadlinesDoNotInventDates() {
        val now = Instant.parse("2026-10-28T10:00:00Z")
        assertNull(DueDate.resolved("irgendwann", now, now))
        assertNull(DueDate.resolved("am 32.13.2026", now, now))
        assertNull(DueDate.spokenClock("morgen um acht oder um neun"))
        assertNull(DueDate.resolved("um acht", now, now))
        assertNull(DueDate.resolved("in 9223372036854775807 Wochen", now, now))
        assertNull(DueDate.resolved("quarter past nonsense pm", now, now))
        val english = DueDate.resolved("quarter past nine pm", now, now)!!
        assertFalse(english.hasTime)
        assertEquals(21, english.date.atZone(java.time.ZoneId.systemDefault()).hour)
    }
}
