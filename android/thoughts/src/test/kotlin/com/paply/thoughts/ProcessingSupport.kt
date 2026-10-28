package com.paply.thoughts

import com.paply.core.*
import com.paply.thoughts.ai.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.*
import java.nio.file.Path
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.CopyOnWriteArrayList

class MockStructurer(
    outcomes: List<StructureOutcome> = emptyList(),
    private val fallback: StructureOutcome = processingSuccess(),
) : ThoughtStructuring {
    private val queue = java.util.concurrent.ConcurrentLinkedQueue(outcomes)
    val inputs = CopyOnWriteArrayList<StructureInput>()
    var onCall: suspend (StructureInput) -> Unit = {}
    val calls
        get() = inputs.size

    fun push(outcome: StructureOutcome) {
        queue.add(outcome)
    }

    override suspend fun structure(input: StructureInput, apiKey: String): StructureOutcome {
        inputs.add(input)
        onCall(input)
        return queue.poll() ?: fallback
    }
}

class MockTranscriber(results: List<TranscriptionResult> = emptyList()) : ThoughtTranscribing {
    private val queue = java.util.concurrent.ConcurrentLinkedQueue(results)
    var calls = 0
        private set

    var onCall: suspend () -> Unit = {}

    fun push(result: TranscriptionResult) {
        queue.add(result)
    }

    override suspend fun transcribe(
        audioURL: Path,
        apiKey: String,
        settings: PaplySettings,
    ): TranscriptionResult {
        calls++
        onCall()
        return queue.poll()
            ?: TranscriptionResult.Success(
                "ähm also die Tomaten im Garten muss ich morgen gießen",
                listOf("de"),
                2.0,
                "whisper-large-v3",
            )
    }
}

class Flags {
    @Volatile var online = true
    @Volatile var key: String? = "test-placeholder"
    @Volatile var busy = false
    var busyChecks = 0

    fun checkBusy(): Boolean {
        busyChecks++
        return busy
    }
}

/**
 * Test-only aggregate and deterministic candidates: deliberately no Local ranking/embedding
 * implementation.
 */
object TestTopicIndex : TopicSummarizing {
    override fun summaries(
        topics: List<Topic>,
        thoughts: List<Thought>,
    ): List<TopicSummarizing.Summary> =
        topics
            .filter { it.mergedInto == null }
            .map { t ->
                val members = thoughts.filter {
                    it.deletedAt == null &&
                        it.state != ThoughtState.recording &&
                        ThoughtStore.resolve(it.topicId, topics)?.id == t.id
                }
                TopicSummarizing.Summary(
                    t,
                    members.size,
                    members.maxOfOrNull { it.createdAt },
                    t.owner == Owner.user || members.size >= 2,
                    members.map { it.id },
                )
            }
}

class TestCandidateFinder(private val store: ThoughtStore) : CandidateFinding, KeywordFinding {
    val changed = CopyOnWriteArrayList<Thought>()

    override suspend fun topicIndex(
        forText: String,
        languages: List<String>,
    ): CandidateFinding.TopicIndex {
        val ss = TestTopicIndex.summaries(store.topics(), store.all())
        return CandidateFinding.TopicIndex(
            ss.map {
                TopicIndexEntry(
                    it.topic.id,
                    it.topic.title,
                    it.count,
                    emptyList(),
                    it.topic.describedNote,
                )
            },
            ss.count { it.isActive } >= 24,
        )
    }

    override suspend fun candidates(forText: String, languages: List<String>, excluding: String) =
        candidates(forText, languages, excluding, Instant.now())

    override suspend fun candidates(
        forText: String,
        languages: List<String>,
        excluding: String,
        relativeTo: Instant,
    ) =
        store
            .all()
            .filter {
                it.id != excluding &&
                    it.deletedAt == null &&
                    it.state == ThoughtState.done &&
                    it.createdAt <= relativeTo
            }
            .sortedByDescending { it.createdAt }
            .take(8)
            .map {
                CandidateEntry(
                    it.id,
                    it.title ?: "",
                    it.topicId,
                    whenLabel(it.createdAt, relativeTo),
                    it.text ?: "",
                    0.8,
                )
            }

    override suspend fun didChange(thought: Thought) {
        changed.add(thought)
    }

    override suspend fun keywords(forText: String, language: String?) =
        TextAnalysis.letterRuns(forText)
            .filter { it.length >= 5 }
            .map { it.lowercase() }
            .distinct()
            .take(5)

    companion object {
        fun whenLabel(at: Instant, relativeTo: Instant): String {
            val zone = ZoneId.systemDefault()
            return if (at.atZone(zone).toLocalDate() == relativeTo.atZone(zone).toLocalDate())
                "heute " + DateTimeFormatter.ofPattern("HH:mm").withZone(zone).format(at)
            else at.toString()
        }
    }
}

class Harness(
    val structurer: MockStructurer = MockStructurer(),
    val transcriber: MockTranscriber = MockTranscriber(),
    options: ThoughtProcessor.Options = ThoughtProcessor.Options(autoRetry = false),
    val onSleep: () -> Unit = {},
    onSettings: suspend () -> Unit = {},
    trace: ThoughtTrace = ThoughtTrace.off,
) : AutoCloseable {
    val root = StoreSupport.temporaryRoot()
    val clock = TestClock()
    val store = ThoughtStore(root, clock.function)
    val flags = Flags()
    val sleeps = CopyOnWriteArrayList<Double>()
    val finder = TestCandidateFinder(store)
    val ledger = TokenLedger(root.resolve("ledger.json"), now = clock.function)
    val processor =
        ThoughtProcessor(
            store,
            structurer,
            finder,
            ledger,
            ProcessorEnvironment(
                { flags.key },
                { flags.online },
                { flags.checkBusy() },
                {
                    onSettings()
                    PaplySettings()
                },
                "de",
            ),
            TestTopicIndex,
            finder,
            transcriber,
            options,
            clock.function,
            {
                sleeps.add(it)
                onSleep()
            },
            trace,
        )

    fun capture(seconds: Double = 1.0): String {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.append(StoreSupport.tone(seconds))
        store.finishCapture(t.id, w.close())
        return t.id
    }

    suspend fun run(reason: String = "test") {
        processor.kick(reason)
        processor.waitUntilIdle()
    }

    fun thought(id: String) = store.thought(id)

    override fun close() {
        processor.close()
        StoreSupport.remove(root)
    }
}

fun processingSuccess(
    title: String = "Tomaten gießen",
    clean: String? = "Die Tomaten im Garten muss ich morgen gießen.",
    topic: TopicDecision = TopicDecision.New("Garten", TopicIcon.leaf),
    tasks: List<TaskDraft> =
        listOf(
            TaskDraft("Tomaten gießen", "die tomaten im garten muss ich morgen gießen", "morgen"),
        ),
    related: List<RelatedDraft> = emptyList(),
    tokens: Int = 3000,
) =
    StructureOutcome.Success(
        StructureResult(title, clean, topic, tasks, related),
        "openai/gpt-oss-120b",
        TokenUsage(tokens - 500, 500, tokens),
    )
