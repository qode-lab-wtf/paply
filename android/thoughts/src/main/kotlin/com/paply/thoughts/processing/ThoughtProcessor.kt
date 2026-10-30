package com.paply.thoughts.processing

import com.paply.core.*
import com.paply.thoughts.*
import com.paply.thoughts.ai.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.model.*
import com.paply.thoughts.processing.ThoughtTrace.Value.*
import com.paply.thoughts.store.*
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.ceil
import kotlin.math.pow
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Serial, restartable queue. All ownership decisions are rechecked inside the store's commit lock.
 */
class ThoughtProcessor(
    private val store: ThoughtStore,
    private val structurer: ThoughtStructuring,
    private val finder: CandidateFinding,
    private val ledger: TokenLedger,
    private val environment: ProcessorEnvironment,
    private val topicIndex: TopicSummarizing,
    private val keywordFinder: KeywordFinding,
    private val transcriber: ThoughtTranscribing = FileTranscriber(),
    val options: Options = Options(),
    private val now: () -> Instant = Instant::now,
    private val sleep: suspend (Double) -> Unit = { delay((it * 1000).toLong().coerceAtLeast(0)) },
    private val trace: ThoughtTrace = ThoughtTrace.off,
    private val languageDetector: LanguageDetector = NoLanguageDetector,
) : AutoCloseable {
    data class Options(
        val maxAttempts: Int = 5,
        val backoffBase: Double = 30.0,
        val backoffMax: Double = 600.0,
        val limitMinimumWait: Double = 900.0,
        val budgetMinimumWait: Double = 60.0,
        val partGap: Double = 60.0,
        val dictationPoll: Double = 1.5,
        val attentionAfter: Double = 86400.0,
        val liveWait: Double = 900.0,
        val promptVersion: Int = ThoughtPrompt.version,
        val autoRetry: Boolean = true,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private val restartMutex = Mutex()
    private var running: Job? = null
    private val restarting = mutableSetOf<Job>()
    private var rerun = false
    private var timer: Job? = null
    private val liveOutcomes = ConcurrentHashMap<String, DictationOutcome>()
    private val expectedLive = ConcurrentHashMap<String, Instant>()
    private val pendingSources = ConcurrentHashMap<String, ThoughtSource>()
    private val rejectedKeyFile = store.root.resolve("rejected-key.sha256").toFile()
    @Volatile private var rejectedKey: String? = if (rejectedKeyFile.exists()) rejectedKeyFile.readText() else null
    private fun keyFingerprint(key: String): String = java.security.MessageDigest.getInstance("SHA-256")
        .digest(key.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    private fun rejectKey(key: String) {
        val fingerprint = keyFingerprint(key)
        rejectedKeyFile.writeText(fingerprint)
        rejectedKey = fingerprint
    }
    private val eventBroadcast = Broadcast<ProcessorEvent>()
    val events
        get() = eventBroadcast.stream

    fun expectLiveTranscript(id: String) {
        expectedLive[id] = now()
    }

    fun cancelLiveTranscript(id: String) {
        expectedLive.remove(id)
        liveOutcomes.remove(id)
    }

    fun liveTranscript(id: String, outcome: DictationOutcome) {
        liveOutcomes[id] = outcome
        expectedLive.remove(id)
        kick("live")
    }

    fun kick(reason: String) {
        synchronized(lock) {
            if (running != null) {
                rerun = true
                return
            }
            val job = scope.launch(start = CoroutineStart.LAZY) { drain() }
            running = job
            job.start()
        }
    }

    fun reorganize(id: String) {
        synchronized(lock) {
            val job =
                scope.launch(start = CoroutineStart.LAZY) { restartMutex.withLock { restart(id) } }
            restarting.add(job)
            job.invokeOnCompletion { synchronized(lock) { restarting.remove(job) } }
            job.start()
        }
    }

    private fun restart(id: String) {
        val t = store.thought(id) ?: return
        if (t.deletedAt != null || t.state == ThoughtState.recording) return
        store.discardAIResult(id)
        val transcribed = store.hasSource(id) || pendingSources.containsKey(id)
        runCatching {
            store.update(id) {
                it.copy(
                    state = if (transcribed) ThoughtState.transcribed else ThoughtState.captured,
                    status = Thought.Status(),
                )
            }
        }
        kick("reorganize")
    }

    suspend fun waitUntilIdle() {
        while (true) {
            val jobs = synchronized(lock) { restarting.toList() + listOfNotNull(running) }
            if (jobs.isEmpty()) return
            jobs.joinAll()
        }
    }

    fun cancelRunning() {
        synchronized(lock) { running?.cancel() }
    }

    override fun close() {
        scope.cancel()
        eventBroadcast.finish()
    }

    fun nextRetryDate(): Instant? =
        store
            .all()
            .filter { it.deletedAt == null && isWaiting(it.state) }
            .mapNotNull { it.status.retryAt }
            .filter { it > now() }
            .minOrNull()

    fun hasPendingWork() =
        store.all().any {
            it.deletedAt == null &&
                it.state != ThoughtState.waitingKey &&
                (isInFlight(it.state) || isWaiting(it.state))
        }

    private suspend fun drain() {
        try {
            while (currentCoroutineContext().isActive) {
                synchronized(lock) { rerun = false }
                val visited = mutableSetOf<String>()
                while (currentCoroutineContext().isActive) {
                    val id = nextItem(visited) ?: break
                    visited.add(id)
                    process(id)
                }
                val again =
                    synchronized(lock) {
                        if (rerun) true
                        else {
                            running = null
                            false
                        }
                    }
                if (!again) break
            }
        } catch (_: CancellationException) {
            /* persisted in-flight states are resumable */
        } finally {
            val job = currentCoroutineContext()[Job]
            synchronized(lock) { if (running == job) running = null }
            scheduleRetry()
        }
    }

    private fun scheduleRetry() {
        synchronized(lock) {
            timer?.cancel()
            timer = null
            if (!options.autoRetry) return
            val next = nextRetryDate() ?: return
            val millis = maxOf(1000, next.toEpochMilli() - now().toEpochMilli())
            timer = scope.launch {
                delay(millis)
                kick("retry")
            }
        }
    }

    private suspend fun nextItem(visited: Set<String>): String? {
        val thoughts = store.all()
        val clock = now()
        val online =
            if (thoughts.any { it.deletedAt == null && it.state == ThoughtState.waitingNetwork })
                environment.isOnline()
            else false
        val key =
            if (thoughts.any { it.deletedAt == null && it.state == ThoughtState.waitingKey })
                environment.apiKey()?.let(TextForm::trim)
            else null
        return thoughts
            .mapNotNull { t ->
                if (t.deletedAt != null || t.id in visited) return@mapNotNull null
                val due = t.status.retryAt?.let { it <= clock } ?: true
                val priority =
                    when (t.state) {
                        ThoughtState.captured -> {
                            val since = expectedLive[t.id]
                            if (
                                since != null &&
                                    !liveOutcomes.containsKey(t.id) &&
                                    seconds(since, clock) < options.liveWait
                            )
                                return@mapNotNull null
                            0
                        }
                        ThoughtState.transcribing,
                        ThoughtState.transcribed,
                        ThoughtState.structuring -> 0
                        ThoughtState.waitingNetwork ->
                            if (due && online) 1 else return@mapNotNull null
                        ThoughtState.waitingKey ->
                            if (!key.isNullOrEmpty() && keyFingerprint(key) != rejectedKey) 1
                            else return@mapNotNull null
                        ThoughtState.waitingLimit,
                        ThoughtState.waitingBudget -> if (due) 1 else return@mapNotNull null
                        else -> return@mapNotNull null
                    }
                priority to t
            }
            .minWithOrNull(
                compareBy<Pair<Int, Thought>> { it.first }
                    .thenBy { it.second.createdAt }
                    .thenBy { it.second.id },
            )
            ?.second
            ?.id
    }

    private suspend fun process(id: String) {
        val t =
            store.thought(id)?.takeIf { it.deletedAt == null && it.state != ThoughtState.recording }
                ?: return
        var source = store.source(id)
        if (source == null)
            pendingSources[id]?.let { pending ->
                if (runCatching { store.saveSourceOnce(id, pending) }.isSuccess)
                    pendingSources.remove(id)
                source = pending
            }
        if (source != null) {
            liveOutcomes.remove(id)
            expectedLive.remove(id)
        } else source = transcribe(t)
        val s = source ?: return
        if (TextForm.trim(s.text).isEmpty()) {
            markEmpty(id)
            return
        }
        store.releaseAudio(
            id,
        ) // store checks durable source, never merely the in-memory pending value
        structure(id, s)
    }

    private suspend fun transcribe(t: Thought): ThoughtSource? {
        val id = t.id
        val settings = environment.settings()
        liveOutcomes.remove(id)?.let { live ->
            expectedLive.remove(id)
            val result = FileTranscriber.result(live, settings.transcriptionModel)
            traceTranscription(id, result, null)
            when (result) {
                TranscriptionResult.NoSpeech -> {
                    markEmpty(id)
                    return null
                }
                is TranscriptionResult.Success -> {
                    val amount = maxOf(1, ceil(result.audioSeconds).toInt())
                    runCatching { ledger.reserve(result.model, amount, TokenLedger.Unit.audio) }
                        .getOrNull()
                        ?.let { ledger.settle(it, amount) }
                    return persistSource(id, result)
                }
                is TranscriptionResult.Failure -> Unit
            }
        }
        expectedLive.remove(id)
        val key = environment.apiKey()?.let(TextForm::trim)
        if (key.isNullOrEmpty()) {
            wait(id, ThoughtState.waitingKey, message = message(ThoughtState.waitingKey))
            return null
        }
        if (keyFingerprint(key) == rejectedKey) {
            wait(id, ThoughtState.waitingKey, message = keyRejectedMessage)
            return null
        }
        if (!environment.isOnline()) {
            wait(id, ThoughtState.waitingNetwork, message = message(ThoughtState.waitingNetwork))
            return null
        }
        val audio =
            store.audioURL(id)
                ?: run {
                    attention(id, "Ton fehlt · nicht verschriftlicht")
                    return null
                }
        if (!waitForDictation(id)) return null
        val amount = maxOf(1, ceil(t.durationMs / 1000.0).toInt())
        val reservation =
            try {
                ledger.reserve(settings.transcriptionModel, amount, TokenLedger.Unit.audio)
            } catch (e: TokenLedger.Refusal) {
                refused(id, e)
                return null
            }
        val current = runCatching {
            store.update(id) {
                if (it.deletedAt == null) it.copy(state = ThoughtState.transcribing) else it
            }
        }
            .getOrNull()
        if (current == null || current.deletedAt != null) {
            ledger.settle(reservation, 0)
            return null
        }
        eventBroadcast.yield(ProcessorEvent.Processing(id))
        trace.log(
            "thought.transcribe.begin",
            mapOf(
                "id" to S(ThoughtTrace.short(id)),
                "model" to S(settings.transcriptionModel),
                "audioS" to ThoughtTrace.Value.ms(t.durationMs / 1000.0),
            ),
        )
        val start = System.nanoTime()
        val result = transcriber.transcribe(audio, key, settings)
        traceTranscription(id, result, start)
        return when (result) {
            is TranscriptionResult.Success -> {
                ledger.settle(reservation, ceil(result.audioSeconds).toInt())
                persistSource(id, result)
            }
            TranscriptionResult.NoSpeech -> {
                ledger.settle(reservation, 0)
                markEmpty(id)
                null
            }
            is TranscriptionResult.Failure -> {
                ledger.settle(reservation, 0)
                transcriptionFailed(id, result.failure, key)
                null
            }
        }
    }

    private fun persistSource(id: String, result: TranscriptionResult.Success): ThoughtSource? {
        val spoken =
            result.languages.ifEmpty {
                listOfNotNull(detectLanguage(result.text, languageDetector))
            }
        val source =
            ThoughtSource(
                result.text,
                PartSplitter.sentences(result.text, id),
                result.model,
                now(),
                spoken,
                result.audioSeconds,
            )
        try {
            store.saveSourceOnce(id, source)
        } catch (e: ThoughtStoreError) {
            if (e.code == ThoughtStoreError.Code.sourceExists) return store.source(id)
            if (e.code == ThoughtStoreError.Code.notFound) return null
            pendingSources[id] = source
        } catch (_: java.io.IOException) {
            pendingSources[id] = source
        }
        runCatching {
            store.update(id) {
                it.copy(
                    state = ThoughtState.transcribed,
                    languages = spoken,
                    status = Thought.Status(),
                )
            }
        }
        return source
    }

    private suspend fun transcriptionFailed(
        id: String,
        failure: TranscriptionFailure,
        key: String,
    ) {
        when (failure) {
            TranscriptionFailure.unauthorized -> {
                rejectKey(key)
                wait(id, ThoughtState.waitingKey, message = keyRejectedMessage)
            }
            TranscriptionFailure.rateLimited -> {
                val at = after(options.limitMinimumWait)
                wait(id, ThoughtState.waitingLimit, at, limitMessage(at))
            }
            TranscriptionFailure.network -> failedAttempt(id, true)
            TranscriptionFailure.server,
            TranscriptionFailure.invalidResponse -> failedAttempt(id, false)
            TranscriptionFailure.modelMissing -> attention(id, "Modell nicht verfügbar")
            TranscriptionFailure.rejected,
            TranscriptionFailure.unreadableAudio ->
                attention(id, message(ThoughtState.needsAttention))
            TranscriptionFailure.cancelled ->
                runCatching { store.update(id) { it.copy(state = ThoughtState.captured) } }
                    .let { Unit }
        }
    }

    private suspend fun failedAttempt(id: String, network: Boolean, transcribed: Boolean = false) {
        val t = store.thought(id) ?: return
        val attempts = t.status.attempts + 1
        if (
            attempts >= options.maxAttempts &&
                (!network || seconds(t.createdAt, now()) >= options.attentionAfter)
        ) {
            val source = if (transcribed) store.source(id) else null
            if (source != null) applyRaw(id, source, if (network) "network" else "server")
            else attention(id, message(ThoughtState.needsAttention), attempts)
            return
        }
        val delay = minOf(options.backoffMax, options.backoffBase * 2.0.pow(attempts - 1))
        wait(
            id,
            ThoughtState.waitingNetwork,
            after(delay),
            if (network) message(ThoughtState.waitingNetwork)
            else "Gesichert · Groq gestört, neuer Versuch gleich",
            attempts,
        )
    }

    private suspend fun structure(id: String, source: ThoughtSource) {
        store.aiResultRecord(id)?.let {
            trace.log("thought.structure.cached", mapOf("id" to S(ThoughtTrace.short(id))))
            apply(id, source, it)
            return
        }
        val key = environment.apiKey()?.let(TextForm::trim)
        if (key.isNullOrEmpty()) {
            wait(id, ThoughtState.waitingKey, message = message(ThoughtState.waitingKey))
            return
        }
        if (keyFingerprint(key) == rejectedKey) {
            wait(id, ThoughtState.waitingKey, message = keyRejectedMessage)
            return
        }
        if (!environment.isOnline()) {
            wait(id, ThoughtState.waitingNetwork, message = message(ThoughtState.waitingNetwork))
            return
        }
        if (!waitForDictation(id)) return
        runCatching {
            store.update(id) {
                if (it.deletedAt == null) it.copy(state = ThoughtState.structuring) else it
            }
        }
        eventBroadcast.yield(ProcessorEvent.Processing(id))
        val settings = environment.settings()
        val topicsAtCall = store.topics()
        val context = finder.topicIndex(source.text, source.languages)
        val recordedAt = store.thought(id)?.createdAt ?: now()
        val candidates = finder.candidates(source.text, source.languages, id, recordedAt)
        val base =
            StructureInput(
                source.text,
                source.sentences,
                source.languages,
                environment.uiLanguage,
                settings.vocabulary,
                context.entries,
                context.full,
                candidates,
                recordedAt = recordedAt,
            )
        val parts = PartSplitter.split(source)
        trace.log(
            "thought.structure.begin",
            mapOf(
                "id" to S(ThoughtTrace.short(id)),
                "textLen" to I(TextForm.count(source.text)),
                "parts" to I(parts.size),
                "topics" to I(context.entries.size),
                "candidates" to I(candidates.size),
            ),
        )
        val start = System.nanoTime()
        var result =
            if (parts.size == 1) structureIfWanted(id, base, key)
            else structureParts(id, source, parts, base, key)
        if (result == StructureOutcome.Unusable("too_large") && parts.size == 1)
            result = structureParts(id, source, PartSplitter.split(source, true), base, key)
        traceStructure(id, result, start)
        when (val outcome = result) {
            null ->
                runCatching {
                    store.update(id) {
                        if (it.deletedAt != null) it.copy(state = ThoughtState.transcribed) else it
                    }
                }
            is StructureOutcome.Success -> {
                val record =
                    AIResultRecord(
                        outcome.result,
                        outcome.model,
                        outcome.usage,
                        now(),
                        label(outcome.result.topic, topicsAtCall, context.entries),
                    )
                runCatching { store.saveAIResult(id, record) }
                apply(id, source, record)
            }
            is StructureOutcome.Wait -> {
                if (outcome.state == ThoughtState.waitingKey) rejectKey(key)
                structureWait(id, outcome)
            }
            is StructureOutcome.Unusable -> applyRaw(id, source, outcome.code)
        }
    }

    private suspend fun structureWait(id: String, outcome: StructureOutcome.Wait) {
        when (outcome.state) {
            ThoughtState.waitingKey ->
                wait(id, ThoughtState.waitingKey, message = keyRejectedMessage)
            ThoughtState.waitingLimit -> {
                val at = maxOf(outcome.retryAt ?: Instant.MIN, after(60.0))
                wait(
                    id,
                    ThoughtState.waitingLimit,
                    at,
                    limitMessage(if (outcome.retryAt == null) null else at),
                )
            }
            ThoughtState.waitingBudget ->
                wait(
                    id,
                    ThoughtState.waitingBudget,
                    maxOf(outcome.retryAt ?: Instant.MIN, after(options.budgetMinimumWait)),
                    message(ThoughtState.waitingBudget),
                )
            ThoughtState.needsAttention ->
                attention(id, outcome.message.ifEmpty { message(ThoughtState.needsAttention) })
            else -> {
                if (!currentCoroutineContext().isActive) {
                    runCatching { store.update(id) { it.copy(state = ThoughtState.transcribed) } }
                    return
                }
                failedAttempt(id, true, true)
            }
        }
    }

    private suspend fun structureIfWanted(
        id: String,
        input: StructureInput,
        key: String,
    ): StructureOutcome? {
        val t = store.thought(id) ?: return null
        if (t.deletedAt != null) return null
        return withContext(ThoughtTrace.ThoughtID(ThoughtTrace.short(id))) {
            structurer.structure(input, key)
        }
    }

    private suspend fun structureParts(
        id: String,
        source: ThoughtSource,
        parts: List<PartSplitter.Part>,
        base: StructureInput,
        key: String,
    ): StructureOutcome? {
        if (parts.size <= 1) return structureIfWanted(id, base, key)
        val hash = StableHash.of(source.text).toString(16)
        var progress =
            store.parts(id)?.takeIf { it.transcriptHash == hash && it.count == parts.size }
                ?: StructureParts(hash, parts.size)
        if (progress.first == null) {
            val outcome =
                structureIfWanted(
                    id,
                    base.copy(transcript = parts[0].text, sentences = parts[0].sentences),
                    key,
                ) ?: return null
            if (outcome !is StructureOutcome.Success) return outcome
            progress =
                progress.copy(
                    first =
                        AIResultFile(
                            AIResultRecord(outcome.result, outcome.model, outcome.usage, now()),
                        ),
                    lastCallAt = now(),
                )
            runCatching { store.saveParts(id, progress) }
        }
        while (progress.rest.size < parts.size - 1) {
            val index = progress.rest.size + 1
            progress.lastCallAt?.let {
                val gap = options.partGap - seconds(it, now())
                if (gap > 0) {
                    trace.log(
                        "thought.wait",
                        mapOf(
                            "id" to S(ThoughtTrace.short(id)),
                            "state" to S("partGap"),
                            "waitS" to ThoughtTrace.Value.ms(gap),
                        ),
                    )
                    sleep(gap)
                }
            }
            if (!currentCoroutineContext().isActive || !waitForDictation(id))
                return StructureOutcome.Wait(ThoughtState.waitingNetwork, null, "Abgebrochen")
            val input =
                base.copy(
                    transcript = parts[index].text,
                    sentences = parts[index].sentences,
                    topics = emptyList(),
                    topicsFull = false,
                    candidates = emptyList(),
                    part = StructureInput.Part(index + 1, parts.size),
                )
            val outcome = structureIfWanted(id, input, key) ?: return null
            val part =
                when (outcome) {
                    is StructureOutcome.Success ->
                        StructureParts.Part(
                            outcome.result.cleanText,
                            outcome.result.tasks.map { StructureParts.StoredTask(it) },
                            outcome.result.rejections,
                            outcome.usage.total,
                        )
                    is StructureOutcome.Unusable ->
                        StructureParts.Part(null, emptyList(), listOf(outcome.code), 0)
                    is StructureOutcome.Wait -> return outcome
                }
            progress = progress.copy(rest = progress.rest + part, lastCallAt = now())
            runCatching { store.saveParts(id, progress) }
        }
        val first = progress.first?.record ?: return StructureOutcome.Unusable("parts")
        val texts =
            listOf(first.result.cleanText ?: RawText.tidy(parts[0].text)) +
                progress.rest.mapIndexed { i, p -> p.cleanText ?: RawText.tidy(parts[i + 1].text) }
        val allRaw = first.result.cleanText == null && progress.rest.all { it.cleanText == null }
        val tasks =
            (first.result.tasks + progress.rest.flatMap { it.tasks.map { t -> t.draft } })
                .distinctBy { RawText.taskKey(it.text, it.dueHint) }
        val combined =
            first.result.copy(
                cleanText = if (allRaw) null else texts.joinToString("\n\n"),
                tasks = tasks,
                rejections =
                    (first.result.rejections + progress.rest.flatMap { it.rejections }).distinct(),
            )
        val firstUsage = first.usage ?: TokenUsage(0, 0, 0)
        return StructureOutcome.Success(
            combined,
            first.model ?: ThoughtStructurer.primaryModel,
            firstUsage.copy(total = firstUsage.total + progress.rest.sumOf { it.tokens }),
        )
    }

    private suspend fun apply(id: String, source: ThoughtSource, record: AIResultRecord) {
        val current = store.thought(id)?.takeIf { it.deletedAt == null } ?: return
        val r = record.result
        val clock = now()
        val aiTopic =
            if (current.topicOwner != Owner.user) resolveTopic(r.topic, record.chosenTopic)
            else null
        val links =
            r.related
                .filter { it.thoughtID != id }
                .mapNotNull { related ->
                    store
                        .thought(related.thoughtID)
                        ?.takeIf { it.deletedAt == null }
                        ?.let { ThoughtLink(it.id, related.kind, related.reason, Owner.ai, clock) }
                }
        val keywords =
            keywordFinder.keywords(
                r.title + "\n" + (r.cleanText ?: source.text),
                source.languages.firstOrNull(),
            )
        val drafts =
            r.tasks.map { d ->
                val due = DueDate.resolved(d.dueHint, current.createdAt, clock)
                ThoughtTask(
                    text = d.text,
                    quote = d.quote,
                    dueHint = d.dueHint,
                    dueAt = due?.date,
                    dueHasTime = due?.hasTime,
                    owner = Owner.ai,
                    createdAt = clock,
                )
            }
        val raw = RawText.tidy(source.text)
        val ai =
            Thought.AIInfo(
                record.model ?: "",
                options.promptVersion,
                record.usage?.total ?: 0,
                clock,
                r.rejections,
            )
        val updated =
            runCatching {
                store.update(id, aiTopic) { t, chosen ->
                    if (t.deletedAt != null) return@update t
                    val kept = t.tasks.filter { it.owner == Owner.user || it.done }
                    val userLinks = t.links.filter { it.origin == Owner.user }
                    val linked = userLinks.map { it.target }.toSet()
                    t.copy(
                        title =
                            if (t.titleOwner == Owner.user) t.title
                            else
                                r.title.takeIf { TextForm.trim(it).isNotEmpty() }
                                    ?: RawText.fallbackTitle(r.cleanText ?: raw),
                        titleOwner = if (t.titleOwner == Owner.user) Owner.user else Owner.ai,
                        text = if (t.textOwner == Owner.user) t.text else r.cleanText ?: raw,
                        textIsRaw =
                            if (t.textOwner == Owner.user) t.textIsRaw else r.cleanText == null,
                        textOwner = if (t.textOwner == Owner.user) Owner.user else Owner.ai,
                        topicId = if (t.topicOwner == Owner.user) t.topicId else chosen,
                        topicOwner = if (t.topicOwner == Owner.user) Owner.user else Owner.ai,
                        tasks = kept + drafts.filter { d -> kept.none { RawText.sameTask(it, d) } },
                        links = userLinks + links.filter { it.target !in linked },
                        languages = source.languages,
                        keywords = keywords,
                        ai = ai,
                        state = ThoughtState.done,
                        status = Thought.Status(),
                    )
                }
            }
                .getOrNull() ?: return
        if (updated.state != ThoughtState.done || updated.deletedAt != null) return
        saved(updated)
    }

    private suspend fun applyRaw(id: String, source: ThoughtSource, code: String) {
        if (store.thought(id)?.deletedAt != null) return
        val raw = RawText.tidy(source.text)
        val keywords = keywordFinder.keywords(raw, source.languages.firstOrNull())
        val ai = Thought.AIInfo("", options.promptVersion, 0, now(), listOf(code))
        val updated =
            runCatching {
                store.update(id) { t ->
                    if (t.deletedAt != null) return@update t
                    val text = if (t.textOwner == Owner.user) t.text else raw
                    t.copy(
                        text = text,
                        textIsRaw = if (t.textOwner == Owner.user) t.textIsRaw else true,
                        textOwner = if (t.textOwner == Owner.user) Owner.user else Owner.ai,
                        title =
                            if (t.titleOwner == Owner.user) t.title
                            else RawText.fallbackTitle(text ?: raw),
                        titleOwner = if (t.titleOwner == Owner.user) Owner.user else Owner.ai,
                        topicId = if (t.topicOwner == Owner.user) t.topicId else null,
                        tasks = t.tasks.filter { it.owner == Owner.user || it.done },
                        links = t.links.filter { it.origin == Owner.user },
                        languages = source.languages,
                        keywords = keywords,
                        ai = ai,
                        state = ThoughtState.done,
                        status = Thought.Status(),
                    )
                }
            }
                .getOrNull() ?: return
        if (updated.state == ThoughtState.done && updated.deletedAt == null) saved(updated)
    }

    private suspend fun saved(t: Thought) {
        store.discardParts(t.id)
        finder.didChange(t)
        val topic = store.resolveTopic(t.topicId)
        eventBroadcast.yield(ProcessorEvent.Saved(t.id, topic?.title, topic?.icon))
    }

    private fun resolveTopic(decision: TopicDecision, chosen: TopicLabel?): Topic? {
        val topics = store.topics()
        return when (decision) {
            TopicDecision.None -> null
            is TopicDecision.Existing ->
                ThoughtStore.resolve(decision.id, topics)
                    ?: chosen?.let { newTopic(it.name, it.icon, topics, true) }
            is TopicDecision.New -> newTopic(decision.name, decision.icon, topics, false)
        }
    }

    private fun newTopic(
        name: String,
        icon: TopicIcon,
        topics: List<Topic>,
        restoring: Boolean,
    ): Topic? {
        val same = TopicHygiene.sameNamedTopics(name, topics)
        if (same.size == 1) return same[0]
        if (same.isNotEmpty()) return null
        if (restoring) {
            if (TextForm.trim(name).isEmpty()) return null
        } else if (
            !TopicHygiene.isValidNewName(name) ||
                topicIndex.summaries(topics, store.all()).count { it.isActive } >=
                    TopicHygiene.maxActiveTopics
        )
            return null
        return Topic(title = TextForm.trim(name), icon = icon, owner = Owner.ai, createdAt = now())
    }

    private fun wait(
        id: String,
        state: ThoughtState,
        retryAt: Instant? = null,
        message: String,
        attempts: Int? = null,
    ) {
        val updated = runCatching {
            store.update(id) {
                it.copy(
                    state = state,
                    status = Thought.Status(message, attempts ?: it.status.attempts, retryAt),
                )
            }
        }
            .getOrNull()
        if (updated != null) eventBroadcast.yield(ProcessorEvent.Waiting(id, state, message))
        val fields =
            mutableMapOf<String, ThoughtTrace.Value>(
                "id" to S(ThoughtTrace.short(id)),
                "state" to S(state.name),
            )
        retryAt?.let { fields["waitS"] = ThoughtTrace.Value.ms(maxOf(0.0, seconds(now(), it))) }
        attempts?.let { fields["attempts"] = I(it) }
        trace.log("thought.wait", fields)
    }

    private fun attention(id: String, message: String, attempts: Int? = null) {
        val updated = runCatching {
            store.update(id) {
                it.copy(
                    state = ThoughtState.needsAttention,
                    status = Thought.Status(message, attempts ?: it.status.attempts, null),
                )
            }
        }
            .getOrNull()
        if (updated != null) eventBroadcast.yield(ProcessorEvent.Failed(id, message))
        val fields =
            mutableMapOf<String, ThoughtTrace.Value>(
                "id" to S(ThoughtTrace.short(id)),
                "why" to S(attentionCode(message)),
            )
        attempts?.let { fields["attempts"] = I(it) }
        trace.log("thought.attention", fields)
    }

    private fun refused(id: String, e: TokenLedger.Refusal) {
        when (e) {
            TokenLedger.Refusal.BudgetTooSmall -> attention(id, "Budget zu klein")
            is TokenLedger.Refusal.Budget ->
                wait(
                    id,
                    ThoughtState.waitingBudget,
                    maxOf(e.retryAt, after(options.budgetMinimumWait)),
                    message(ThoughtState.waitingBudget),
                )
            is TokenLedger.Refusal.Minute ->
                wait(
                    id,
                    ThoughtState.waitingBudget,
                    maxOf(e.retryAt, after(options.budgetMinimumWait)),
                    message(ThoughtState.waitingBudget),
                )
        }
    }

    private fun markEmpty(id: String) {
        store.purge(id)
        pendingSources.remove(id)
        eventBroadcast.yield(ProcessorEvent.Empty(id))
        trace.log("thought.empty", mapOf("id" to S(ThoughtTrace.short(id))))
    }

    private suspend fun waitForDictation(id: String): Boolean {
        var started: Long? = null
        while (environment.isDictationBusy()) {
            if (started == null) started = System.nanoTime()
            if (!currentCoroutineContext().isActive) break
            sleep(options.dictationPoll)
        }
        started?.let {
            trace.log(
                "thought.wait.dictation",
                mapOf("id" to S(ThoughtTrace.short(id)), "ms" to ThoughtTrace.milliseconds(it)),
            )
        }
        return currentCoroutineContext().isActive
    }

    private fun traceTranscription(id: String, result: TranscriptionResult, started: Long?) {
        val fields =
            mutableMapOf<String, ThoughtTrace.Value>(
                "id" to S(ThoughtTrace.short(id)),
                "live" to B(started == null),
            )
        started?.let { fields["ms"] = ThoughtTrace.milliseconds(it) }
        when (result) {
            is TranscriptionResult.Success -> {
                fields["result"] = S("ok")
                fields["textLen"] = I(TextForm.count(result.text))
                fields["langs"] =
                    S(
                        result.languages
                            .filter { Regex("[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?").matches(it) }
                            .joinToString(","),
                    )
                fields["audioS"] = ThoughtTrace.Value.ms(result.audioSeconds)
                fields["model"] = S(result.model)
            }
            TranscriptionResult.NoSpeech -> fields["result"] = S("noSpeech")
            is TranscriptionResult.Failure -> fields["result"] = S(result.failure.name)
        }
        trace.log("thought.transcribe.end", fields)
    }

    private fun traceStructure(id: String, outcome: StructureOutcome?, started: Long) {
        val f =
            mutableMapOf<String, ThoughtTrace.Value>(
                "id" to S(ThoughtTrace.short(id)),
                "ms" to ThoughtTrace.milliseconds(started),
            )
        when (outcome) {
            null -> f["result"] = S("cancelled")
            is StructureOutcome.Success -> {
                val r = outcome.result
                f["result"] = S("ok")
                f["model"] = S(outcome.model)
                f["fallback"] = B(outcome.model != ThoughtStructurer.primaryModel)
                f["tokens"] = I(outcome.usage.total)
                f["tasks"] = I(r.tasks.size)
                f["topic"] =
                    S(
                        when (r.topic) {
                            is TopicDecision.Existing -> "existing"
                            is TopicDecision.New -> "new"
                            TopicDecision.None -> "none"
                        },
                    )
                f["links"] = I(r.related.size)
                f["textIsRaw"] = B(r.cleanText == null)
                f["rejections"] = I(r.rejections.size)
            }
            is StructureOutcome.Wait -> {
                f["result"] = S("wait")
                f["code"] = S(outcome.state.name)
            }
            is StructureOutcome.Unusable -> {
                f["result"] = S("raw")
                f["code"] = S(outcome.code)
            }
        }
        trace.log("thought.structure.end", f)
    }

    private fun after(seconds: Double) = now().plusMillis((seconds * 1000).toLong())

    companion object {
        private fun seconds(a: Instant, b: Instant) = (b.toEpochMilli() - a.toEpochMilli()) / 1000.0

        fun isInFlight(state: ThoughtState) =
            state in
                listOf(
                    ThoughtState.captured,
                    ThoughtState.transcribing,
                    ThoughtState.transcribed,
                    ThoughtState.structuring,
                )

        fun isWaiting(state: ThoughtState) =
            state in
                listOf(
                    ThoughtState.waitingNetwork,
                    ThoughtState.waitingKey,
                    ThoughtState.waitingLimit,
                    ThoughtState.waitingBudget,
                )

        fun label(
            decision: TopicDecision,
            topics: List<Topic>,
            index: List<TopicIndexEntry>,
        ): TopicLabel? {
            if (decision !is TopicDecision.Existing) return null
            return ThoughtStore.resolve(decision.id, topics)?.let { TopicLabel(it.title, it.icon) }
                ?: index
                    .firstOrNull { it.topicID == decision.id }
                    ?.let { TopicLabel(it.name, TopicIcon.sparkles) }
        }

        const val keyRejectedMessage = "Gesichert · Groq-Schlüssel ungültig"

        fun message(state: ThoughtState) =
            when (state) {
                ThoughtState.waitingNetwork -> "Gesichert · wartet auf Netz"
                ThoughtState.waitingKey -> "Gesichert · Groq-Schlüssel fehlt"
                ThoughtState.waitingLimit -> "Gesichert · Groq-Limit, später"
                ThoughtState.waitingBudget -> "Gesichert · Kontingent für heute erreicht"
                ThoughtState.needsAttention -> "Ton gesichert · nicht verschriftlicht"
                else -> ""
            }

        fun limitMessage(retryAt: Instant?) =
            if (retryAt == null) message(ThoughtState.waitingLimit)
            else
                "Gesichert · Groq-Limit, ab ca. " +
                    DateTimeFormatter.ofPattern("HH:mm")
                        .withZone(ZoneId.systemDefault())
                        .format(retryAt)

        fun attentionCode(text: String) =
            when (text) {
                "Ton fehlt · nicht verschriftlicht" -> "audioMissing"
                "Modell nicht verfügbar" -> "modelMissing"
                "Budget zu klein" -> "budgetTooSmall"
                message(ThoughtState.needsAttention) -> "failed"
                else -> "other"
            }
    }
}
