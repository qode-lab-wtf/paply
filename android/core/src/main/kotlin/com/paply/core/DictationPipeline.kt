@file:Suppress("DEPRECATION")

package com.paply.core

import java.io.File
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*

/**
 * One recording session. append is synchronous/thread-safe; network tasks start at pauses during
 * recording. Call cancel/close when the owner is disposed. finish is idempotent; retry retains
 * successful pieces. State callbacks are serialized with state changes on the calling/worker
 * thread: Android must dispatch UI work.
 */
class DictationPipeline
internal constructor(
    settings: PaplySettings,
    private val client: GroqClient,
    private val catalog: ModelCatalog = ModelCatalog.shared,
    private val options: PipelineOptions = PipelineOptions(),
    recentRawDictations: List<String> = emptyList(),
    deviceLanguages: List<String> = listOf(Locale.getDefault().toLanguageTag()),
    private val encoder: AudioEncoding = DefaultAudioEncoding(),
    private val detector: LanguageDetector = NoLanguageDetector,
    private val clock: PaplyClock = SystemPaplyClock,
    private val onState: (DictationStatus) -> Unit = {},
) : AutoCloseable {
    constructor(
        configuration: DictationConfiguration,
        options: PipelineOptions = PipelineOptions(),
        recentRawDictations: List<String> = emptyList(),
        encoder: AudioEncoding = DefaultAudioEncoding(),
        detector: LanguageDetector = NoLanguageDetector,
        clock: PaplyClock = SystemPaplyClock,
        reachability: NetworkReachability = AssumeReachable,
        onState: (DictationStatus) -> Unit = {},
    ) : this(
        configuration.settings(),
        GroqClient(configuration.keyProvider(), clock = clock, reachability = reachability),
        ModelCatalog.shared,
        options,
        recentRawDictations,
        configuration.deviceLanguages,
        encoder,
        detector,
        clock,
        onState,
    )

    @Deprecated(
        "Create a session with DictationConfiguration and feed append(samples), then finish()",
    )
    constructor(client: GroqClient) : this(PaplySettings(), client)

    companion object {
        const val maxPieceSeconds = 600.0
        const val previousTextWaitMillis = 1500L
    }

    private val lock = Any()
    private val settings = settings.copy(spokenLanguages = settings.spokenLanguages.toList())
    private val recentRawDictations = recentRawDictations.toList()
    private val deviceLanguages = deviceLanguages.toList()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val samples = PcmBuffer()
    private var vad = VoiceActivityDetector()
    private var planner = ChunkPlanner()

    private data class Chunk(
        val start: Int,
        val end: Int,
        val task: Deferred<ChunkResult>,
        var result: ChunkResult? = null,
    )

    internal data class ChunkResult(
        val text: String = "",
        val segments: List<WhisperSegment> = emptyList(),
        val language: String? = null,
        val failure: GroqFailure? = null,
        val sent: Boolean = true,
        val languageSource: LanguageSource? = null,
    ) {
        val succeeded
            get() = sent && failure == null
    }

    private data class PlanPiece(val start: Int, val end: Int, var result: ChunkResult? = null)

    private val chunks = mutableListOf<Chunk>()
    private var chunkingStopped = false
    private var plan: MutableList<PlanPiece>? = null
    private var finishTask: Deferred<DictationOutcome>? = null
    private var finishing = false
    private var finished = false
    private var cancelled = false
    private var audioReleased = false
    private var lastOutcome: DictationOutcome? = null
    private var lastFailed = false
    private val bytes = AtomicInteger()
    private val uploads = AtomicInteger()
    private var state = DictationState.recording
    private val primer
        get() =
            if (options.codeSwitchPrimer)
                CodeSwitchPrimer.text(CodeSwitchPrimer.userLanguages(settings, deviceLanguages))
            else null

    val speechDetected
        get() = synchronized(lock) { vad.speechDetected }

    val levelDbfs
        get() = synchronized(lock) { vad.lastLevelDbfs }

    val canRetry
        get() =
            synchronized(lock) { lastFailed && !audioReleased && !cancelled && samples.size > 0 }

    private fun notifyState(next: DictationState = state) {
        state = next
        // An observer must not turn an otherwise successful recording into a failure.
        try {
            onState(DictationStatus(next, vad.speechDetected, vad.lastLevelDbfs))
        } catch (_: Exception) {}
    }

    fun append(samples: ShortArray) = appendPcm(samples, AudioEncoder.floats(samples))

    /** Float entry point retained for parity tests and callers with a resampler. */
    fun append(samples: FloatArray) = appendPcm(AudioEncoder.int16(samples), samples)

    private fun appendPcm(pcm: ShortArray, floating: FloatArray) =
        synchronized(lock) {
            if (finished || cancelled || pcm.isEmpty()) return@synchronized
            samples.append(pcm)
            vad.process(floating)
            notifyState()
            if (
                finished ||
                    cancelled ||
                    !settings.chunkedUpload ||
                    !vad.speechDetected ||
                    chunkingStopped
            )
                return@synchronized
            while (true) {
                val range = planner.nextCut(vad) ?: break
                startChunk(range)
            }
        }

    fun discardSilentStart(): Boolean =
        synchronized(lock) {
            if (finished || cancelled || chunks.isNotEmpty() || vad.speechDetected)
                return@synchronized false
            samples.clear()
            vad = VoiceActivityDetector()
            planner = ChunkPlanner()
            true
        }

    private fun startChunk(range: IntRange) {
        val n = VoiceActivityDetector.frameLength
        val start = range.first * n
        val end = minOf((range.last + 1) * n, samples.size)
        if (end <= start) return
        val audio = samples.copy(start, end)
        val measured = vad.snapshot()
        if (chunks.isEmpty() && options.polish) catalog.cachedModels(client)
        val previous = chunks.lastOrNull()?.task
        val task =
            scope.async(start = CoroutineStart.LAZY) {
                val before =
                    if (previous != null)
                        withTimeoutOrNull(previousTextWaitMillis) { previous.await() }
                    else null
                currentCoroutineContext().ensureActive()
                if (synchronized(lock) { chunkingStopped }) return@async ChunkResult(sent = false)
                transcribe(audio, start, measured, before).also { result ->
                    synchronized(lock) {
                        chunks.firstOrNull { it.start == start }?.result = result
                        if (result.failure != null && result.failure.code != "cancelled")
                            chunkingStopped = true
                    }
                }
            }
        chunks += Chunk(start, end, task)
        task.start()
    }

    private suspend fun transcribe(
        audio: ShortArray,
        startSample: Int,
        measured: VoiceActivityDetector,
        previous: ChunkResult?,
    ): ChunkResult {
        val prompt = WhisperPrompt.build(settings.vocabulary, previous?.text, primer)
        val encoded =
            encoder.encode(audio, options.uploadFormat == PipelineOptions.UploadFormat.flac)
        currentCoroutineContext().ensureActive()
        val seconds = audio.size / AudioEncoder.sampleRate
        suspend fun send(language: String?): Transcription {
            uploads.incrementAndGet()
            return client.transcribe(
                encoded,
                settings.transcriptionModel,
                language,
                prompt,
                seconds,
            ) {
                bytes.addAndGet(it)
            }
        }
        val users = CodeSwitchPrimer.userLanguages(settings, deviceLanguages)
        val primary =
            LanguageGuard.primary(settings.primaryLanguage, users, deviceLanguages.firstOrNull())
        val previousLanguage = previous?.takeIf { it.succeeded && it.text.isNotEmpty() }?.language
        val n = VoiceActivityDetector.frameLength
        val firstFrame = startSample / n
        val lastFrame = (startSample + audio.size + n - 1) / n
        val range = maxOf(0, firstFrame) until minOf(lastFrame, measured.frameCount)
        val spoken = if (range.isEmpty()) seconds else measured.activity(range).speechMs / 1000
        val first =
            LanguageGuard.firstRequest(settings.language, primary, previousLanguage, users, spoken)
        var source = first.source
        var sentLanguage = first.language
        var result =
            try {
                send(first.language)
            } catch (f: GroqFailure) {
                return ChunkResult(failure = f)
            }
        if (source == LanguageSource.auto) {
            val redo =
                LanguageGuard.redoLanguage(GroqModels.languageCode(result.language), primary, users)
            if (redo != null)
                try {
                    result = send(redo)
                    source = LanguageSource.redo
                    sentLanguage = redo
                } catch (_: GroqFailure) {
                    source = LanguageSource.redoFailed
                }
        }
        currentCoroutineContext().ensureActive()
        val filtered =
            SilenceFilter.filter(
                result.text,
                result.segments,
                measured.meta(firstFrame until lastFrame),
            )
        val offset = startSample / AudioEncoder.sampleRate
        val cleaned =
            TranscriptCleanup.removeEchoes(
                filtered.text,
                filtered.keptSegments,
                primer,
                previous?.text,
                settings.vocabulary,
                seconds,
            ) { from, to ->
                measured.voicedMs(offset + from, offset + to)
            }
        val text = if (SilenceFilter.isTrivialTranscript(cleaned.text)) "" else cleaned.text
        val segments =
            if (text.isEmpty()) emptyList()
            else
                cleaned.segments.map {
                    it.copy(start = it.start?.plus(offset), end = it.end?.plus(offset))
                }
        val guarded =
            if (source == LanguageSource.short || source == LanguageSource.redo)
                sentLanguage?.let(CodeSwitchPrimer::baseCode)
            else null
        return ChunkResult(
            text,
            segments,
            guarded ?: GroqModels.languageCode(result.language) ?: detectLanguage(text, detector),
            languageSource = source,
        )
    }

    suspend fun finish(): DictationOutcome = awaitFinish(false)

    suspend fun retry(): DictationOutcome = awaitFinish(true)

    private suspend fun awaitFinish(retry: Boolean): DictationOutcome {
        val task =
            synchronized(lock) {
                if (cancelled) return DictationOutcome(error = DictationError.cancelled)
                if (retry && !finishing) {
                    lastOutcome
                        ?.takeIf { !lastFailed }
                        ?.let {
                            return it
                        }
                    if (audioReleased)
                        return DictationOutcome(
                            errorMessage = "Die Aufnahme ist nicht mehr verfügbar.",
                            error = DictationError.audioUnavailable,
                        )
                }
                if (finishTask != null && (!retry || finishing)) finishTask!!
                else {
                    finished = true
                    finishing = true
                    scope
                        .async(start = CoroutineStart.LAZY) {
                            try {
                                runFinish()
                            } finally {
                                synchronized(lock) { finishing = false }
                            }
                        }
                        .also {
                            finishTask = it
                            it.start()
                        }
                }
            }
        return try {
            task.await()
        } catch (e: CancellationException) {
            cancel()
            if (!currentCoroutineContext().isActive) throw e
            DictationOutcome(error = DictationError.cancelled)
        }
    }

    fun releaseAudio() =
        synchronized(lock) {
            if (!finished || finishing) return@synchronized
            audioReleased = true
            samples.clear()
            plan = null
        }

    fun cancel() =
        synchronized(lock) {
            if (cancelled) return@synchronized
            cancelled = true
            finished = true
            chunkingStopped = true
            scope.cancel()
            samples.clear()
            plan = null
            notifyState(DictationState.cancelled)
        }

    override fun close() = cancel()

    private suspend fun runFinish(): DictationOutcome {
        val started = clock.monotonicNanos()
        fun ms() = (clock.monotonicNanos() - started) / 1e6
        val bytesBefore: Int
        val uploadsBefore: Int
        val audio: ShortArray
        val measured: VoiceActivityDetector
        synchronized(lock) {
            bytesBefore = if (plan == null) 0 else bytes.get()
            uploadsBefore = if (plan == null) 0 else uploads.get()
            audio = samples.copy(0, samples.size)
            measured = vad.snapshot()
        }
        var timings = DictationTimings(audioSeconds = audio.size / AudioEncoder.sampleRate)
        fun done(outcome: DictationOutcome, failed: Boolean = false): DictationOutcome =
            synchronized(lock) {
                if (cancelled)
                    return@synchronized DictationOutcome(error = DictationError.cancelled)
                val out =
                    outcome.copy(
                        timings =
                            timings.copy(
                                totalMs = ms(),
                                uploadedBytes = bytes.get() - bytesBefore,
                                chunkCount = uploads.get() - uploadsBefore,
                            ),
                        languageSources =
                            plan.orEmpty().mapNotNull { it.result?.languageSource?.rawValue },
                    )
                lastFailed = failed
                if (!failed) lastOutcome = out
                notifyState(if (failed) DictationState.failed else DictationState.finished)
                if (cancelled) DictationOutcome(error = DictationError.cancelled) else out
            }
        currentCoroutineContext().ensureActive()
        if (
            audio.isEmpty() ||
                !measured.speechDetected ||
                SilenceFilter.shouldSkipTranscription(measured.meta())
        ) {
            synchronized(lock) { chunks.forEach { it.task.cancel() } }
            return done(DictationOutcome(noSpeech = true))
        }
        if (options.polish) catalog.cachedModels(client)
        synchronized(lock) { if (!cancelled) notifyState(DictationState.transcribing) }
        val running = synchronized(lock) { chunks.toList() }
        for (chunk in running) if (chunk.result == null) {
            val result = chunk.task.await()
            synchronized(lock) { chunk.result = result }
        }
        currentCoroutineContext().ensureActive()
        val pieces =
            synchronized(lock) { plan ?: makePlan(audio.size, measured).also { plan = it } }
        var failure: GroqFailure? = null
        for (index in pieces.indices) if (pieces[index].result?.succeeded != true) {
            val piece = pieces[index]
            val previous = pieces.take(index).lastOrNull { it.result?.succeeded == true }?.result
            val result =
                transcribe(
                    audio.copyOfRange(piece.start, piece.end),
                    piece.start,
                    measured,
                    previous,
                )
            currentCoroutineContext().ensureActive()
            if (result.failure != null) {
                failure = result.failure
                break
            }
            piece.result = result
        }
        timings = timings.copy(transcriptionDoneMs = ms())
        if (failure != null)
            return done(
                DictationOutcome(
                    errorMessage = failure.germanMessage,
                    error = failure.dictationError,
                ),
                failed = true,
            )
        val results = pieces.mapNotNull { it.result }
        val raw = TranscriptCleanup.join(results.map { it.text })
        val languages = results.mapNotNull { it.language }.distinct()
        if (raw.isEmpty()) return done(DictationOutcome(languages = languages, noSpeech = true))
        if (!options.polish)
            return done(
                DictationOutcome(
                    text = raw,
                    raw = raw,
                    languages = languages,
                    polishError = PolishFailureCode.disabled.rawValue,
                ),
            )
        synchronized(lock) { if (!cancelled) notifyState(DictationState.polishing) }
        val messages =
            PolishPrompt.buildMessages(
                raw,
                recentRawDictations,
                results.flatMap { it.segments },
                settings.vocabulary,
            )
        val polish =
            PolishService(client, catalog, options.strictPolishCheck)
                .polish(raw, messages, settings.vocabulary, settings)
        timings = timings.copy(polishDoneMs = ms())
        currentCoroutineContext().ensureActive()
        return done(
            DictationOutcome(
                text = polish.polished ?: raw,
                raw = raw,
                polished = polish.polished,
                polishRejection = polish.rejection,
                languages = languages,
                polishError = polish.error?.rawValue,
                polishModel = polish.model,
            ),
        )
    }

    private fun makePlan(
        sampleCount: Int,
        measured: VoiceActivityDetector,
    ): MutableList<PlanPiece> {
        val pieces = mutableListOf<PlanPiece>()
        fun addPending(start: Int, end: Int) {
            val last = pieces.lastOrNull()
            if (last != null && last.result == null && last.end == start)
                pieces[pieces.lastIndex] = PlanPiece(last.start, end)
            else pieces += PlanPiece(start, end)
        }
        for (chunk in chunks) if (chunk.result?.succeeded == true)
            pieces += PlanPiece(chunk.start, chunk.end, chunk.result)
        else addPending(chunk.start, chunk.end)
        val tailStart = chunks.lastOrNull()?.end ?: 0
        if (tailStart < sampleCount) {
            val tail = tailStart / VoiceActivityDetector.frameLength until measured.frameCount
            val pendingBefore = pieces.lastOrNull()?.let { it.result == null } ?: false
            if (chunks.isEmpty() || pendingBefore || measured.hasAnyActivity(tail))
                addPending(tailStart, sampleCount)
        }
        return pieces.flatMap { split(it, measured) }.toMutableList()
    }

    private fun split(piece: PlanPiece, measured: VoiceActivityDetector): List<PlanPiece> {
        if (piece.result != null) return listOf(piece)
        val limit = (maxPieceSeconds * AudioEncoder.sampleRate).toInt()
        val parts = mutableListOf<PlanPiece>()
        var start = piece.start
        while (piece.end - start > limit) {
            val n = VoiceActivityDetector.frameLength
            val lastFrame = (start + limit) / n
            val firstFrame =
                maxOf(start / n + 1, lastFrame - (30_000 / VoiceActivityDetector.frameMs).toInt())
            var cutFrame = lastFrame
            var quietest = Float.MAX_VALUE
            for (frame in firstFrame until minOf(lastFrame, measured.frameCount)) if (
                measured.frames[frame].dbfs < quietest
            ) {
                quietest = measured.frames[frame].dbfs
                cutFrame = frame
            }
            val cut = maxOf(start + 1, minOf(cutFrame * n, piece.end))
            parts += PlanPiece(start, cut)
            start = cut
        }
        parts += PlanPiece(start, piece.end)
        return parts
    }

    @Deprecated("Use append(samples) and finish(); Phase-0 adapter only")
    suspend fun dictate(wav: File, seconds: Double): DictationResult =
        polish(client.transcribe(wav, seconds))

    @Deprecated("Use a recording session and finish(); Phase-0 adapter only")
    suspend fun polish(raw: Transcript): DictationResult {
        if (raw.text.isBlank()) return DictationResult("", "", null, null)
        val result =
            PolishService(client, catalog)
                .polish(
                    raw.text,
                    PolishPrompt.buildMessages(raw.text, segments = raw.segments.map { it.core() }),
                    "",
                    settings,
                )
        return DictationResult(
            raw.text,
            result.polished ?: raw.text,
            result.model,
            result.rejection ?: result.error?.rawValue,
        )
    }
}

private class PcmBuffer {
    private var data = ShortArray(0)
    var size = 0
        private set

    fun append(samples: ShortArray) {
        val end = Math.addExact(size, samples.size)
        if (end > data.size) data = data.copyOf(maxOf(end, maxOf(16000, data.size * 2)))
        samples.copyInto(data, size)
        size = end
    }

    fun copy(start: Int, end: Int) = data.copyOfRange(start, end)

    fun clear() {
        data = ShortArray(0)
        size = 0
    }
}
