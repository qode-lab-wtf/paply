package com.paply.thoughts

import com.paply.core.*
import com.paply.thoughts.ai.*
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.*
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

class ProcessingTests {
    @Test
    fun capturedThoughtIsTranscribedStructuredAndKeepsNoSound() = runBlocking {
        Harness().use { h ->
            val events = h.processor.events
            val id = h.capture(2.0)
            h.run()
            val t = h.thought(id)!!
            assertEquals(ThoughtState.done, t.state)
            assertEquals("Tomaten gießen", t.title)
            assertEquals(Owner.ai, t.titleOwner)
            assertEquals("Die Tomaten im Garten muss ich morgen gießen.", t.text)
            assertFalse(t.textIsRaw)
            assertEquals(listOf("Tomaten gießen"), t.tasks.map { it.text })
            assertEquals("morgen", t.tasks.first().dueHint)
            assertEquals(3000, t.ai?.tokens)
            assertTrue(t.keywords.isNotEmpty())
            assertNull(t.audio)
            assertFalse(Files.exists(h.store.wavURL(id)))
            assertFalse(Files.exists(h.store.m4aURL(id)))
            assertEquals("Garten", h.store.resolveTopic(t.topicId)?.title)
            assertEquals(Owner.ai, h.store.resolveTopic(t.topicId)?.owner)
            assertEquals(
                "ähm also die Tomaten im Garten muss ich morgen gießen",
                h.store.source(id)?.text,
            )
            assertEquals("${id}_s0", h.store.source(id)?.sentences?.first()?.id)
            assertNotNull(h.store.aiResult(id))
            assertEquals(1, h.transcriber.calls)
            assertEquals(1, h.structurer.calls)
            val input = h.structurer.inputs.first()
            assertNull(input.part)
            assertEquals("de", input.uiLanguage)
            assertEquals("low", input.reasoningEffort)
            val seen = withTimeout(2000) { events.take(3).toList() }
            assertTrue(ProcessorEvent.Processing(id) in seen)
            assertEquals(ProcessorEvent.Saved(id, "Garten", TopicIcon.leaf), seen.last())
        }
    }

    @Test
    fun offlineWaitsAndResumesWhenNetworkReturns() = runBlocking {
        Harness().use { h ->
            h.flags.online = false
            val id = h.capture()
            h.run()
            assertEquals(ThoughtState.waitingNetwork, h.thought(id)?.state)
            assertEquals("Gesichert · wartet auf Netz", h.thought(id)?.status?.message)
            h.run()
            assertEquals(0, h.transcriber.calls)
            h.store.housekeeping(h.clock.now.plusSeconds(40 * 86400))
            assertNotNull(h.store.audioURL(id))
            h.flags.online = true
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(1, h.transcriber.calls)
            assertNull(h.thought(id)?.audio)
            assertFalse(Files.exists(h.store.wavURL(id)))
        }
    }

    @Test
    fun missingKeyWaitsUntilKeyIsEntered() = runBlocking {
        Harness().use { h ->
            h.flags.key = null
            val id = h.capture()
            h.run()
            assertEquals(ThoughtState.waitingKey, h.thought(id)?.state)
            assertEquals("Gesichert · Groq-Schlüssel fehlt", h.thought(id)?.status?.message)
            h.flags.key = "new-placeholder"
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
        }
    }

    @Test
    fun rejectedKeyIsNotRetriedUntilItChanges() = runBlocking {
        Harness(MockStructurer(listOf(StructureOutcome.Wait(ThoughtState.waitingKey, null, "401"))))
            .use { h ->
                val id = h.capture()
                h.run()
                assertEquals(ThoughtState.waitingKey, h.thought(id)?.state)
                h.run()
                assertEquals(1, h.structurer.calls)
                h.flags.key = "other-placeholder"
                h.run()
                assertEquals(2, h.structurer.calls)
                assertEquals(ThoughtState.done, h.thought(id)?.state)
            }
    }

    @Test
    fun limitWaitsUntilRetryTime() = runBlocking {
        Harness(
                MockStructurer(
                    listOf(StructureOutcome.Wait(ThoughtState.waitingLimit, null, "429")),
                ),
            )
            .use { h ->
                val id = h.capture()
                h.run()
                val at = h.thought(id)!!.status.retryAt!!
                assertTrue(at >= h.clock.now.plusSeconds(60))
                assertEquals(at, h.processor.nextRetryDate())
                h.run()
                assertEquals(1, h.structurer.calls)
                h.clock.now = at.plusSeconds(1)
                h.run()
                assertEquals(ThoughtState.done, h.thought(id)?.state)
                assertEquals(2, h.structurer.calls)
                assertEquals(1, h.transcriber.calls)
            }
    }

    @Test
    fun budgetWaitUsesLedgerTime() = runBlocking {
        val later = Instant.ofEpochSecond(1793200000)
        Harness(
                MockStructurer(
                    listOf(StructureOutcome.Wait(ThoughtState.waitingBudget, later, "Budget")),
                ),
            )
            .use { h ->
                val id = h.capture()
                h.run()
                assertEquals(ThoughtState.waitingBudget, h.thought(id)?.state)
                assertEquals(later, h.thought(id)?.status?.retryAt)
                assertEquals(
                    "Gesichert · Kontingent für heute erreicht",
                    h.thought(id)?.status?.message,
                )
            }
    }

    @Test
    fun restartInStructuringUsesCachedResultWithoutNewCalls() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.store.saveSourceOnce(id, StoreSupport.source("die tomaten gießen", h.clock.now))
            h.store.saveAIResult(
                id,
                AIResultRecord(
                    StructureResult(
                        "Aus dem Cache",
                        "Die Tomaten gießen.",
                        TopicDecision.None,
                        emptyList(),
                        emptyList(),
                    ),
                    "openai/gpt-oss-120b",
                    TokenUsage(1, 1, 2),
                ),
            )
            h.store.update(id) { it.copy(state = ThoughtState.structuring) }
            h.run()
            assertEquals("Aus dem Cache", h.thought(id)?.title)
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(0, h.transcriber.calls)
            assertEquals(0, h.structurer.calls)
        }
    }

    @Test
    fun restartInStructuringWithoutCacheAsksOnceMore() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.store.saveSourceOnce(id, StoreSupport.source("die tomaten gießen", h.clock.now))
            h.store.update(id) { it.copy(state = ThoughtState.structuring) }
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(0, h.transcriber.calls)
            assertEquals(1, h.structurer.calls)
        }
    }

    @Test
    fun deletedDuringStructuringIsNotApplied() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.structurer.onCall = { h.store.delete(id) }
            h.run()
            val t = h.thought(id)!!
            assertNotNull(t.deletedAt)
            assertNotEquals(ThoughtState.done, t.state)
            assertNull(t.title)
            assertNotNull(h.store.aiResult(id))
            assertTrue(h.store.topics().isEmpty())
            h.store.restore(id)
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(1, h.structurer.calls)
        }
    }

    @Test
    fun topicPrunedDuringTheCallIsCreatedAgain() = runBlocking {
        Harness(
                MockStructurer(
                    listOf(processingSuccess(topic = TopicDecision.Existing("t_boats"))),
                ),
            )
            .use { h ->
                h.store.saveTopics(
                    listOf(
                        Topic(
                            id = "t_boats",
                            title = "Boote",
                            icon = TopicIcon.flag,
                            owner = Owner.user,
                        ),
                    ),
                )
                val old =
                    StoreSupport.thought(
                        createdAt = h.clock.now.minusSeconds(600),
                        topicId = "t_boats",
                    )
                h.store.save(old)
                h.structurer.onCall = { h.store.purge(old.id) }
                val id = h.capture()
                h.run()
                val t = h.thought(id)!!
                val topic = h.store.resolveTopic(t.topicId)!!
                assertEquals(ThoughtState.done, t.state)
                assertEquals(Owner.ai, t.topicOwner)
                assertEquals(1, h.store.topics().size)
                assertEquals("Boote", topic.title)
                assertEquals(TopicIcon.flag, topic.icon)
                assertEquals(
                    TopicLabel("Boote", TopicIcon.flag),
                    h.store.aiResultRecord(id)?.chosenTopic,
                )
            }
    }

    @Test
    fun cachedResultRecreatesAVanishedTopic() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.store.saveSourceOnce(id, StoreSupport.source("die boote streichen", h.clock.now))
            h.store.saveAIResult(
                id,
                AIResultRecord(
                    StructureResult(
                        "Boote streichen",
                        "Die Boote streichen.",
                        TopicDecision.Existing("t_gone"),
                        emptyList(),
                        emptyList(),
                    ),
                    chosenTopic = TopicLabel("Boote", TopicIcon.flag),
                ),
            )
            h.store.update(id) { it.copy(state = ThoughtState.structuring) }
            h.run()
            val topic = h.store.resolveTopic(h.thought(id)?.topicId)!!
            assertEquals("Boote", topic.title)
            assertEquals(TopicIcon.flag, topic.icon)
            assertEquals(Owner.ai, topic.owner)
            assertEquals(0, h.structurer.calls)
        }
    }

    @Test
    fun reorganizeKeepsTheSameTaskOnAnotherDay() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.run()
            h.store.update(id) {
                it.copy(
                    tasks = it.tasks.map { task -> task.copy(done = true, doneAt = h.clock.now) },
                )
            }
            h.structurer.push(
                processingSuccess(
                    tasks =
                        listOf(
                            TaskDraft("Tomaten gießen", "tomaten", "morgen"),
                            TaskDraft("Tomaten gießen", "tomaten", "übermorgen"),
                        ),
                ),
            )
            h.processor.reorganize(id)
            h.processor.waitUntilIdle()
            val tasks = h.thought(id)!!.tasks
            assertEquals(listOf("morgen", "übermorgen"), tasks.map { it.dueHint })
            assertEquals(listOf(true, false), tasks.map { it.done })
            assertNotNull(tasks[1].dueAt)
            assertEquals(false, tasks[1].dueHasTime)
        }
    }

    @Test
    fun userFieldsSurviveReorganize() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.run()
            val own = Topic(title = "Balkon", icon = TopicIcon.home, owner = Owner.user)
            h.store.saveTopics(h.store.topics() + own)
            h.store.update(id) {
                it.copy(
                    title = "Mein Titel",
                    titleOwner = Owner.user,
                    topicId = own.id,
                    topicOwner = Owner.user,
                    tasks =
                        it.tasks.map { task -> task.copy(done = true, doneAt = h.clock.now) } +
                            ThoughtTask(text = "Erde kaufen", owner = Owner.user),
                )
            }
            h.structurer.push(
                processingSuccess(
                    "KI-Titel",
                    "Neuer Text.",
                    TopicDecision.New("Gemüse", TopicIcon.leaf),
                    listOf(
                        TaskDraft("Tomaten gießen", "tomaten"),
                        TaskDraft("Dünger holen", "dünger"),
                    ),
                ),
            )
            h.processor.reorganize(id)
            h.processor.waitUntilIdle()
            val t = h.thought(id)!!
            assertEquals("Mein Titel", t.title)
            assertEquals(own.id, t.topicId)
            assertEquals("Neuer Text.", t.text)
            assertEquals(
                listOf("Tomaten gießen", "Erde kaufen", "Dünger holen"),
                t.tasks.map { it.text },
            )
            assertTrue(t.tasks[0].done)
            assertEquals(2, h.structurer.calls)
            assertEquals(1, h.transcriber.calls)
            assertEquals("KI-Titel", h.store.aiResult(id)?.title)
            assertFalse(h.store.topics().any { it.title == "Gemüse" })
        }
    }

    @Test
    fun liveTranscriptAvoidsSecondWhisperCall() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.processor.expectLiveTranscript(id)
            h.run()
            assertEquals(ThoughtState.captured, h.thought(id)?.state)
            h.processor.liveTranscript(
                id,
                DictationOutcome(
                    raw = "die tomaten gießen",
                    languages = listOf("de"),
                    timings = DictationTimings(audioSeconds = 1.0),
                ),
            )
            h.processor.waitUntilIdle()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(0, h.transcriber.calls)
            assertEquals("die tomaten gießen", h.store.source(id)?.text)
            assertNull(h.thought(id)?.audio)
        }
    }

    @Test
    fun failedLiveTranscriptFallsBackToFile() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.processor.liveTranscript(
                id,
                DictationOutcome(errorMessage = GroqFailure().germanMessage),
            )
            h.processor.waitUntilIdle()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(1, h.transcriber.calls)
        }
    }

    @Test
    fun nothingSaidRemovesThought() = runBlocking {
        Harness(transcriber = MockTranscriber(listOf(TranscriptionResult.NoSpeech))).use { h ->
            val events = h.processor.events
            val id = h.capture()
            h.run()
            assertNull(h.thought(id))
            assertFalse(Files.exists(h.store.directory(id)))
            assertEquals(
                ProcessorEvent.Empty(id),
                withTimeout(2000) { events.first { it is ProcessorEvent.Empty } },
            )
        }
    }

    @Test
    fun serverErrorsEndInNeedsAttentionAfterFiveAttempts() = runBlocking {
        Harness(
                transcriber =
                    MockTranscriber(
                        List(5) { TranscriptionResult.Failure(TranscriptionFailure.server) },
                    ),
            )
            .use { h ->
                val id = h.capture()
                val delays = mutableListOf<Long>()
                repeat(5) {
                    h.run()
                    h.thought(id)!!.status.retryAt?.let {
                        delays.add(it.epochSecond - h.clock.now.epochSecond)
                        h.clock.now = it
                    }
                }
                assertEquals(listOf(30L, 60L, 120L, 240L), delays)
                assertEquals(ThoughtState.needsAttention, h.thought(id)?.state)
                assertEquals(
                    "Ton gesichert · nicht verschriftlicht",
                    h.thought(id)?.status?.message,
                )
                assertNotNull(h.store.audioURL(id))
                h.run()
                assertEquals(5, h.transcriber.calls)
                h.processor.reorganize(id)
                h.processor.waitUntilIdle()
                assertEquals(ThoughtState.done, h.thought(id)?.state)
                assertEquals(6, h.transcriber.calls)
                assertNull(h.store.audioURL(id))
            }
    }

    @Test
    fun networkErrorsBackOffWithoutGivingUpEarly() = runBlocking {
        Harness(
                transcriber =
                    MockTranscriber(
                        List(7) { TranscriptionResult.Failure(TranscriptionFailure.network) },
                    ),
            )
            .use { h ->
                val id = h.capture()
                repeat(7) { i ->
                    h.run()
                    if (i < 6) h.clock.now = h.thought(id)!!.status.retryAt!!
                }
                val t = h.thought(id)!!
                assertEquals(ThoughtState.waitingNetwork, t.state)
                assertEquals(7, t.status.attempts)
                assertEquals(h.clock.now.plusSeconds(600), t.status.retryAt)
            }
    }

    @Test
    fun unusableResultKeepsRawText() = runBlocking {
        Harness(MockStructurer(listOf(StructureOutcome.Unusable("invalid_output")))).use { h ->
            val id = h.capture()
            h.run()
            val t = h.thought(id)!!
            assertEquals(ThoughtState.done, t.state)
            assertTrue(t.textIsRaw)
            assertEquals("Ähm also die Tomaten im Garten muss ich morgen gießen", t.text)
            assertEquals("Ähm also die Tomaten im Garten …", t.title)
            assertNull(t.topicId)
            assertTrue(t.tasks.isEmpty())
            assertEquals(listOf("invalid_output"), t.ai?.rejections)
        }
    }

    @Test
    fun dictationHasPriority() = runBlocking {
        var flags: Flags? = null
        Harness(onSleep = { flags?.let { if (it.busyChecks >= 3) it.busy = false } }).use { h ->
            flags = h.flags
            h.flags.busy = true
            val id = h.capture()
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertTrue(h.flags.busyChecks >= 4)
            assertTrue(h.sleeps.size >= 3)
        }
    }

    @Test
    fun linksOnlyToExistingThoughtsAndExistingTopicResolves() = runBlocking {
        Harness().use { h ->
            val old =
                StoreSupport.thought(
                    createdAt = h.clock.now.minusSeconds(3600),
                    title = "Tomaten pflanzen",
                    text = "Im Garten Tomaten pflanzen.",
                )
            h.store.save(old)
            h.store.saveTopics(
                listOf(
                    Topic(
                        id = "t_garden",
                        title = "Garten",
                        icon = TopicIcon.leaf,
                        owner = Owner.user,
                    ),
                    Topic(
                        id = "t_alias",
                        title = "Beet",
                        icon = TopicIcon.leaf,
                        owner = Owner.ai,
                        mergedInto = "t_garden",
                    ),
                ),
            )
            h.structurer.push(
                processingSuccess(
                    topic = TopicDecision.Existing("t_alias"),
                    related =
                        listOf(
                            RelatedDraft(old.id, LinkKind.continues, "Gleiches Beet"),
                            RelatedDraft("s_gibtsnicht", LinkKind.sameMatter, "x"),
                        ),
                ),
            )
            val id = h.capture()
            h.run()
            val t = h.thought(id)!!
            assertEquals("t_garden", t.topicId)
            assertEquals(listOf(old.id), t.links.map { it.target })
            assertEquals(Owner.ai, t.links.first().origin)
            val input = h.structurer.inputs.first()
            assertTrue(input.candidates.any { it.thoughtID == old.id })
            assertFalse(input.candidates.any { it.thoughtID == id })
            assertEquals(listOf("t_garden"), input.topics.map { it.topicID })
        }
    }

    @Test
    fun lateStructuringUsesTheRecordingTime() = runBlocking {
        Harness().use { h ->
            val old = StoreSupport.thought(createdAt = h.clock.now.minusSeconds(3600))
            h.store.save(old)
            val id = h.capture()
            val at = h.thought(id)!!.createdAt
            h.clock.advance(2 * 86400)
            h.run()
            val input = h.structurer.inputs.first()
            assertEquals(at, input.recordedAt)
            val c = input.candidates.first { it.thoughtID == old.id }
            assertEquals(TestCandidateFinder.whenLabel(old.createdAt, at), c.`when`)
            assertTrue(c.`when`.startsWith("heute"))
            assertEquals(ThoughtPrompt.version, h.thought(id)?.ai?.promptVersion)
            assertEquals(ThoughtPrompt.version, ThoughtProcessor.Options().promptVersion)
        }
    }

    @Test
    fun purgeDuringTranscriptionStaysPurged() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.transcriber.onCall = { h.store.purge(id) }
            h.run()
            assertEquals(1, h.transcriber.calls)
            assertEquals(0, h.structurer.calls)
            assertNull(h.thought(id))
            assertFalse(Files.exists(h.store.directory(id)))
            assertNull(ThoughtStore(h.root).thought(id))
            h.run()
            assertEquals(1, h.transcriber.calls)
        }
    }

    @Test
    fun deletedBeforeUploadIsNotTranscribed() = runBlocking {
        var target: String? = null
        var store: ThoughtStore? = null
        Harness(onSettings = { target?.let { store?.delete(it) } }).use { h ->
            store = h.store
            val id = h.capture()
            target = id
            h.run()
            assertEquals(0, h.transcriber.calls)
            assertNotNull(h.thought(id)?.deletedAt)
            assertEquals(ThoughtState.captured, h.thought(id)?.state)
            target = null
            h.store.restore(id)
            h.run()
            assertEquals(1, h.transcriber.calls)
            assertEquals(ThoughtState.done, h.thought(id)?.state)
        }
    }

    @Test
    fun deletedBeforeStructuringIsNotSent() = runBlocking {
        var calls = 0
        var target: String? = null
        var store: ThoughtStore? = null
        Harness(
                onSettings = {
                    calls++
                    if (calls == 2) target?.let { store?.delete(it) }
                },
            )
            .use { h ->
                store = h.store
                val id = h.capture()
                target = id
                h.run()
                assertEquals(1, h.transcriber.calls)
                assertEquals(0, h.structurer.calls)
                assertNotNull(h.thought(id)?.deletedAt)
                assertEquals(ThoughtState.transcribed, h.thought(id)?.state)
                assertNull(h.thought(id)?.audio)
                h.store.restore(id)
                h.run()
                assertEquals(1, h.structurer.calls)
                assertEquals(1, h.transcriber.calls)
                assertEquals(ThoughtState.done, h.thought(id)?.state)
            }
    }

    @Test
    fun discardedCaptureNeverReachesGroq() = runBlocking {
        Harness().use { h ->
            val (t, w) = h.store.beginCapture(ThoughtTrigger.control, h.clock.now)
            w.append(StoreSupport.tone(1.0))
            h.store.finishCapture(t.id, w.close(), h.clock.now)
            val saved = h.thought(t.id)!!
            assertEquals(ThoughtState.captured, saved.state)
            assertEquals(h.clock.now, saved.deletedAt)
            assertTrue(saved.durationMs > 0)
            h.run()
            assertEquals(0, h.transcriber.calls)
            assertEquals(0, h.structurer.calls)
            h.store.restore(t.id)
            h.run()
            assertEquals(ThoughtState.done, h.thought(t.id)?.state)
        }
    }

    @Test
    fun cancelledLiveTranscriptDoesNotDelayARestore() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.processor.expectLiveTranscript(id)
            h.store.delete(id)
            h.processor.cancelLiveTranscript(id)
            h.store.restore(id)
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(1, h.transcriber.calls)
            val waiting = h.capture()
            h.processor.expectLiveTranscript(waiting)
            h.run()
            assertEquals(ThoughtState.captured, h.thought(waiting)?.state)
            assertEquals(1, h.transcriber.calls)
        }
    }

    @Test
    fun newTopicMatchingExistingNameReusesIt() = runBlocking {
        Harness(
                MockStructurer(
                    listOf(
                        processingSuccess(topic = TopicDecision.New("Wohnungen", TopicIcon.home)),
                    ),
                ),
            )
            .use { h ->
                h.store.saveTopics(
                    listOf(
                        Topic(
                            id = "t_flat",
                            title = "Wohnung",
                            icon = TopicIcon.home,
                            owner = Owner.ai,
                        ),
                    ),
                )
                val id = h.capture()
                h.run()
                assertEquals("t_flat", h.thought(id)?.topicId)
                assertEquals(1, h.store.topics().size)
            }
    }

    @Test
    fun ambiguousNewTopicStaysWithoutTopic() = runBlocking {
        Harness(
                MockStructurer(
                    listOf(
                        processingSuccess(topic = TopicDecision.New("paply app", TopicIcon.code)),
                    ),
                ),
            )
            .use { h ->
                val topics =
                    listOf(
                        Topic(
                            id = "t_app1",
                            title = "Paply App",
                            icon = TopicIcon.code,
                            owner = Owner.user,
                        ),
                        Topic(
                            id = "t_app2",
                            title = "Paply-App",
                            icon = TopicIcon.code,
                            owner = Owner.ai,
                        ),
                    )
                h.store.saveTopics(topics)
                val id = h.capture()
                h.run()
                assertEquals(ThoughtState.done, h.thought(id)?.state)
                assertNull(h.thought(id)?.topicId)
                assertEquals(topics, h.store.topics())
            }
    }

    private val long =
        "Und dann müssen wir noch die Umzugskartons im Keller zählen und beschriften damit nichts verloren geht. "
            .repeat(70)

    @Test
    fun longThoughtUsesPartsWithGapAndCombinesResult() = runBlocking {
        val mock =
            MockStructurer(
                listOf(
                    processingSuccess(
                        "Umzug planen",
                        "Teil eins.",
                        TopicDecision.New("Umzug", TopicIcon.home),
                        listOf(TaskDraft("Kartons zählen", "kartons")),
                    ),
                    processingSuccess(
                        "",
                        null,
                        TopicDecision.None,
                        listOf(
                            TaskDraft("Kartons zählen", "kartons"),
                            TaskDraft("Kartons beschriften", "beschriften"),
                        ),
                    ),
                ),
            )
        Harness(
                mock,
                MockTranscriber(
                    listOf(
                        TranscriptionResult.Success(long, listOf("de"), 420.0, "whisper-large-v3"),
                    ),
                ),
            )
            .use { h ->
                val id = h.capture()
                h.run()
                val inputs = mock.inputs
                assertEquals(2, inputs.size)
                assertNull(inputs[0].part)
                assertEquals(StructureInput.Part(2, 2), inputs[1].part)
                assertTrue(inputs[1].topics.isEmpty() && inputs[1].candidates.isEmpty())
                assertTrue(inputs.all { PartSplitter.estimateTokens(it.transcript) <= 1400 })
                assertTrue(h.sleeps.any { it > 50 })
                val t = h.thought(id)!!
                assertEquals(ThoughtState.done, t.state)
                assertEquals("Umzug planen", t.title)
                assertTrue(t.text!!.startsWith("Teil eins.\n\n"))
                assertFalse(t.textIsRaw)
                assertEquals(
                    listOf("Kartons zählen", "Kartons beschriften"),
                    t.tasks.map { it.text },
                )
                assertEquals(6000, t.ai?.tokens)
                assertNull(h.store.parts(id))
            }
    }

    @Test
    fun partsProgressSurvivesWaiting() = runBlocking {
        Harness(
                MockStructurer(
                    listOf(
                        processingSuccess(),
                        StructureOutcome.Wait(ThoughtState.waitingLimit, null, "429"),
                        processingSuccess(),
                    ),
                ),
                MockTranscriber(
                    listOf(
                        TranscriptionResult.Success(long, listOf("de"), 420.0, "whisper-large-v3"),
                    ),
                ),
            )
            .use { h ->
                val id = h.capture()
                h.run()
                assertEquals(ThoughtState.waitingLimit, h.thought(id)?.state)
                assertNotNull(h.store.parts(id)?.first)
                h.clock.advance(3600)
                h.run()
                assertEquals(ThoughtState.done, h.thought(id)?.state)
                assertEquals(3, h.structurer.calls)
            }
    }

    @Test
    fun softDiscardedThoughtIsNeverProcessedUntilRestored() = runBlocking {
        Harness().use { h ->
            val id = h.capture()
            h.store.delete(id)
            h.run()
            h.processor.liveTranscript(
                id,
                DictationOutcome(raw = "die tomaten gießen", languages = listOf("de")),
            )
            h.processor.waitUntilIdle()
            assertEquals(ThoughtState.captured, h.thought(id)?.state)
            assertNull(h.store.source(id))
            assertEquals(0, h.transcriber.calls)
            assertEquals(0, h.structurer.calls)
            h.store.restore(id)
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(0, h.transcriber.calls)
            assertEquals("die tomaten gießen", h.store.source(id)?.text)
        }
    }

    @Test
    fun topicHygieneAsksOnceAndStoresSuggestions() = runBlocking {
        Harness().use { h ->
            val topics =
                listOf(
                        "Wohnung",
                        "Wohnungen",
                        "Garten",
                        "Fitness",
                        "Lesen",
                        "Urlaub",
                        "Auto",
                        "Familie",
                    )
                    .mapIndexed { i, n ->
                        Topic(
                            title = n,
                            icon = TopicIcon.list,
                            owner = if (i < 2) Owner.ai else Owner.user,
                        )
                    }
            h.store.saveTopics(topics)
            val a = topics[0].id
            val b = topics[1].id
            listOf(a, a, b, b).forEach { h.store.save(StoreSupport.thought(topicId = it)) }
            MockWebServer().use { s ->
                s.enqueue(
                    AIFixture.reply(
                        """{"pairs":[{"a":"$a","b":"$b","merge":true,"name":"Wohnung","reason":"gleiches Vorhaben"}]}""",
                        total = 500,
                    ),
                )
                val now = h.clock.now
                val result =
                    TopicHygieneRunner.run(
                        h.store,
                        h.ledger,
                        "test-placeholder",
                        TestTopicIndex,
                        baseURL = s.url("/"),
                        now = now,
                    ) as TopicHygieneRunner.Outcome.Suggestions
                assertEquals(1, result.suggestions.size)
                val suggestion = result.suggestions.first()
                assertEquals(setOf(a, b), setOf(suggestion.a, suggestion.b))
                assertEquals("Wohnung", suggestion.name)
                assertEquals("gleiches Vorhaben", suggestion.reason)
                assertEquals(result.suggestions, h.store.pendingSuggestions())
                assertNotNull(h.store.topicsInfo().lastHygieneAt)
                assertEquals("openai/gpt-oss-20b", s.body()["model"]!!.jsonPrimitive.content)
                assertEquals(500, h.ledger.summary().tokens)
                assertEquals(
                    TopicHygieneRunner.Outcome.NotDue,
                    TopicHygieneRunner.run(
                        h.store,
                        h.ledger,
                        "test-placeholder",
                        TestTopicIndex,
                        baseURL = s.url("/"),
                        now = now.plusSeconds(86400),
                    ),
                )
                h.store.declineMerge(a, b)
                assertEquals(
                    TopicHygieneRunner.Outcome.Suggestions(emptyList()),
                    TopicHygieneRunner.run(
                        h.store,
                        h.ledger,
                        "test-placeholder",
                        TestTopicIndex,
                        force = true,
                        baseURL = s.url("/"),
                        now = now,
                    ),
                )
                assertEquals(1, s.requestCount)
                assertEquals(topics, h.store.topics()) // hygiene never applies its proposal
            }
        }
    }

    @Test
    fun partSplitterKeepsShortTranscriptsWhole() {
        assertEquals(1, PartSplitter.split(StoreSupport.source("Kurz.")).size)
        val words = List(3000) { "wort" }.joinToString(" ")
        val parts = PartSplitter.split(StoreSupport.source(words))
        assertEquals(4, parts.size)
        assertTrue(parts.all { it.tokens <= 1400 })
        assertEquals(words, parts.joinToString(" ") { it.text })
    }

    @Test
    fun partSplitterCutsBeforeHesitationsInUnpunctuatedText() {
        val j =
            javaClass
                .getResourceAsStream("/eval.jsonl")!!
                .bufferedReader()
                .readLines()
                .map { Json.parseToJsonElement(it).jsonObject }
                .first { it["id"]?.jsonPrimitive?.content == "e35" }
        val text = j["transcript"]!!.jsonPrimitive.content
        val parts =
            PartSplitter.split(
                StoreSupport.source(text).copy(sentences = PartSplitter.sentences(text, "s_e35")),
            )
        assertEquals(2, parts.size)
        assertTrue(parts.all { it.tokens <= 1400 })
        assertTrue(
            parts.drop(1).all {
                it.text.substringBefore(' ').lowercase() in PartSplitter.hesitations
            },
        )
        assertEquals(
            text.split(Regex("\\s+")).joinToString(" "),
            parts.joinToString(" ") { it.text },
        )
        assertTrue(parts.minOf { it.tokens }.toDouble() / parts.maxOf { it.tokens } > 0.6)
        assertTrue(parts.all { it.sentences.first().id == "s_e35_s0" })
    }

    @Test
    fun partSplitterPrefersSentenceEndsThenMarkersThenLength() {
        val text =
            "Wir müssen die Kartons im Keller zählen und beschriften, damit nichts verloren geht. "
                .repeat(80)
        val parts =
            PartSplitter.split(
                StoreSupport.source(text).copy(sentences = PartSplitter.sentences(text, "s_p")),
            )
        assertEquals(2, parts.size)
        assertTrue(parts.all { it.text.startsWith("Wir müssen") && it.text.endsWith("geht.") })
        val words =
            (0 until 700).joinToString(" ") {
                if (it % 50 == 0 && it > 0) "also" else "wort${it%7}"
            }
        val marked = PartSplitter.split(StoreSupport.source(words), true)
        assertEquals(2, marked.size)
        assertTrue(marked[1].text.startsWith("also "))
        val plain = List(2000) { "wort" }.joinToString(" ")
        val byLength = PartSplitter.split(StoreSupport.source(plain))
        assertEquals(3, byLength.size)
        assertTrue(byLength.all { it.tokens in 901..1400 })
        assertEquals(
            0.0,
            PartSplitter.words(
                    listOf(ThoughtSource.Sentence("a", "ich gehe raus um zu laufen")),
                    listOf("de"),
                )[3]
                .boundary,
            0.0,
        )
        assertEquals(
            3.0,
            PartSplitter.words(
                    listOf(ThoughtSource.Sentence("a", "so I think um we should go")),
                    listOf("en"),
                )[3]
                .boundary,
            0.0,
        )
    }

    @Test
    fun transcriptionErrorsAreClassified() {
        listOf(
                401 to TranscriptionFailure.unauthorized,
                403 to TranscriptionFailure.unauthorized,
                429 to TranscriptionFailure.rateLimited,
                503 to TranscriptionFailure.server,
                404 to TranscriptionFailure.modelMissing,
                400 to TranscriptionFailure.rejected,
            )
            .forEach { (s, k) ->
                assertEquals(k, FileTranscriber.classify(GroqFailure(s).germanMessage))
            }
        assertEquals(
            TranscriptionFailure.network,
            FileTranscriber.classify(GroqFailure().germanMessage),
        )
        assertEquals(
            TranscriptionFailure.invalidResponse,
            FileTranscriber.classify(GroqFailure(code = "invalid-response").germanMessage),
        )
        assertEquals(
            TranscriptionResult.NoSpeech,
            FileTranscriber.result(DictationOutcome(noSpeech = true), "w"),
        )
        assertEquals(
            TranscriptionResult.Failure(TranscriptionFailure.cancelled),
            FileTranscriber.result(DictationOutcome(), "w"),
        )
    }

    @Test
    fun fileTranscriberMakesExactlyOneWhisperRequest() = runBlocking {
        val root = StoreSupport.temporaryRoot()
        try {
            MockWebServer().use { s ->
                s.dispatcher =
                    object : Dispatcher() {
                        override fun dispatch(request: RecordedRequest): MockResponse =
                            if (request.path!!.endsWith("/models"))
                                MockResponse()
                                    .setBody(
                                        """{"data":[{"id":"whisper-large-v3","active":true}]}""",
                                    )
                            else
                                MockResponse()
                                    .setBody(
                                        """{"text":"die tomaten im garten gießen","language":"de","duration":5.0}""",
                                    )
                    }
                val url = root.resolve("audio.wav")
                val w = WAVWriter(url)
                w.append(
                    FloatArray(80000) { i ->
                        if (i < 8000 || i >= 72000) 0.0001f
                        else
                            (0.2 *
                                    kotlin.math.sin(i * 0.1) *
                                    (0.55 + 0.45 * kotlin.math.sin(i * 0.003)))
                                .toFloat()
                    },
                )
                w.close()
                ModelCatalog().use { catalog ->
                    val t = FileTranscriber(baseURL = s.url("/"), catalog = catalog)
                    val result =
                        t.transcribe(url, "test-placeholder", PaplySettings(chunkedUpload = true))
                    assertEquals(
                        TranscriptionResult.Success(
                            "die tomaten im garten gießen",
                            listOf("de"),
                            5.0,
                            "whisper-large-v3",
                        ),
                        result,
                    )
                }
                val paths = List(s.requestCount) { s.takeRequest().path }
                assertEquals(1, paths.count { it == "/audio/transcriptions" })
                assertFalse(paths.any { it == "/chat/completions" })
            }
        } finally {
            StoreSupport.remove(root)
        }
    }

    @Test
    fun dueDatesFollowRecordingTime() {
        val processed = Instant.now()
        val recorded = processed.minusSeconds(2 * 86400)
        val tomorrow = DueDate.resolve("morgen", recorded, processed)
        assertEquals(
            recorded.plusSeconds(86400).atZone(ZoneId.systemDefault()).toLocalDate(),
            tomorrow?.atZone(ZoneId.systemDefault())?.toLocalDate(),
        )
        assertNull(DueDate.resolve("irgendwann", recorded, recorded))
        assertNull(DueDate.resolve(null, recorded, recorded))
    }

    @Test
    fun rawTextFallbackHelpers() {
        assertEquals("Ähm also. Das geht so? Ja", RawText.tidy("ähm  also. das geht   so? ja"))
        assertEquals(
            "eins zwei drei vier fünf sechs …",
            RawText.fallbackTitle("eins zwei drei vier fünf sechs sieben"),
        )
        assertEquals("kurz", RawText.fallbackTitle("kurz."))
        assertEquals(RawText.key("Tomaten gießen!"), RawText.key("tomaten giessen"))
    }
}
