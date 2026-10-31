@file:Suppress("DEPRECATION")

package com.paply.core

import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel

/**
 * One recording session. append is synchronous/thread-safe; network tasks start at pauses during
 * recording. Call cancel/close when the owner is disposed. finish is idempotent; retry retains
 * successful pieces. State callbacks are delivered in order on a worker, outside the state lock
 * and recording thread: Android must dispatch UI work. Cancelling a finish waiter retains work.
 */
class DictationPipeline
constructor(
    settings: PaplySettings,
    private val client: GroqClient,
    private val catalog: ModelCatalog = ModelCatalog.shared,
    private val options: PipelineOptions = PipelineOptions(),
    recentRawDictations: List<String> = emptyList(),
    deviceLanguages: List<String> = emptyList(),
    private val encoder: AudioEncoding = DefaultAudioEncoding(),
    private val detector: LanguageDetector = NoLanguageDetector,
    private val clock: PaplyClock = SystemPaplyClock,
    private val onState: (DictationStatus) -> Unit = {},
    private val previousPieceLanguage: String? = null,
) : AutoCloseable {
    constructor(
        configuration: DictationConfiguration,
        options: PipelineOptions = PipelineOptions(),
        recentRawDictations: List<String> = emptyList(),
        encoder: AudioEncoding = DefaultAudioEncoding(),
        detector: LanguageDetector = NoLanguageDetector,
        clock: PaplyClock = SystemPaplyClock,
        reachability: NetworkReachability = AssumeReachable,
        diagnostic: (String) -> Unit = {},
        onState: (DictationStatus) -> Unit = {},
    ) : this(
        configuration.settings(),
        GroqClient(configuration.keyProvider(), clock = clock, reachability = reachability, diagnostic = diagnostic),
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
    private var vad = VoiceActivityDetector(analyzeQuietFrames = true)
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
    @Volatile private var finished = false
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

    private val notifications = Channel<DictationStatus>(Channel.UNLIMITED)
    private val notificationTask = CoroutineScope(Dispatchers.Default).launch {
        for (status in notifications) {
            // Observers cannot block recording or break the pipeline, even if they throw Error.
            try { onState(status) } catch (_: Throwable) {}
        }
    }

    // Called under lock: capture the matching VAD/state, never invoke client code here.
    private fun notifyState(next: DictationState = state) {
        state = next
        notifications.trySend(DictationStatus(next, vad.speechDetected, vad.lastLevelDbfs))
    }

    fun append(samples: ShortArray) {
        if (!finished) appendPcm(samples, AudioEncoder.floats(samples))
    }

    /** Float entry point retained for parity tests and callers with a resampler. */
    fun append(samples: FloatArray) {
        if (!finished) appendPcm(AudioEncoder.int16(samples), samples)
    }

    private fun appendPcm(pcm: ShortArray, floating: FloatArray) {
        val ready = synchronized(lock) {
            if (finished || cancelled || pcm.isEmpty()) return
            samples.append(pcm)
            vad.process(floating)
            notifyState()
            val pending = mutableListOf<Deferred<ChunkResult>>()
            if (settings.chunkedUpload && !options.removeLongSilence && vad.speechDetected && !chunkingStopped) {
                while (true) {
                    val range = planner.nextCut(vad) ?: break
                    prepareChunk(range)?.let { pending += it }
                }
            }
            pending
        }
        // Reservations are already visible to finish/cancel before any task is dispatched.
        ready.forEach(::startChunk)
    }

    fun discardSilentStart(): Boolean =
        synchronized(lock) {
            if (finished || cancelled || chunks.isNotEmpty() || vad.speechDetected)
                return@synchronized false
            samples.clear()
            vad = VoiceActivityDetector(analyzeQuietFrames = true)
            planner = ChunkPlanner()
            true
        }

    private fun startChunk(task: Deferred<ChunkResult>) { task.start() }

    // Under lock: reserve a lazy task so finish cannot miss a cut racing with append.
    private fun prepareChunk(range: IntRange): Deferred<ChunkResult>? {
        val n = VoiceActivityDetector.frameLength
        val start = range.first * n
        val end = minOf((range.last + 1) * n, samples.size)
        if (end <= start) return null
        val audio = samples.copy(start, end)
        val measured = vad.snapshot()
        val warmCatalog = chunks.isEmpty() && options.polish
        val previous = chunks.lastOrNull()?.task
        val task =
            scope.async(start = CoroutineStart.LAZY) {
                if (warmCatalog) catalog.cachedModels(client)
                val before =
                    if (previous != null)
                        awaitChunk(previous)
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
        return task
    }

    private suspend fun awaitChunk(task: Deferred<ChunkResult>): ChunkResult = try {
        task.await()
    } catch (error: Throwable) {
        ChunkResult(failure = error.asGroqFailure())
    }

    private suspend fun transcribe(
        audio: ShortArray,
        startSample: Int,
        measured: VoiceActivityDetector,
        previous: ChunkResult?,
    ): ChunkResult = try {
        // Compact only confidently silent runs; preserve live scheduling and one request per piece.
        val ranges = LongSilence.ranges(measured, startSample, startSample + audio.size)
        if (ranges.isEmpty()) ChunkResult()
        else if (ranges.size == 1 && ranges[0].first == startSample && ranges[0].last + 1 == startSample + audio.size)
            transcribeChecked(audio, startSample, measured, previous)
        else {
            val compact = ShortArray(ranges.sumOf { it.last - it.first + 1 })
            var cursor = 0
            for (range in ranges) {
                audio.copyInto(compact, cursor, range.first - startSample, range.last + 1 - startSample)
                cursor += range.last - range.first + 1
            }
            val local = VoiceActivityDetector(analyzeQuietFrames = true)
            local.process(AudioEncoder.floats(compact))
            fun original(seconds: Double, end: Boolean): Double {
                var sample = (seconds * AudioEncoder.sampleRate).toInt().coerceIn(0, compact.size)
                for (range in ranges) {
                    val size = range.last - range.first + 1
                    if (sample < size || (end && sample == size))
                        return (range.first + sample) / AudioEncoder.sampleRate
                    sample -= size
                }
                return (ranges.last().last + 1) / AudioEncoder.sampleRate
            }
            transcribeChecked(compact, 0, local, previous).let { result ->
                result.copy(segments = result.segments.map { segment ->
                    segment.copy(start = segment.start?.let { original(it, false) },
                        end = segment.end?.let { original(it, true) })
                })
            }
        }
    } catch (error: Throwable) {
        ChunkResult(failure = error.asGroqFailure())
    }

    private suspend fun transcribeChecked(
        audio: ShortArray,
        startSample: Int,
        measured: VoiceActivityDetector,
        previous: ChunkResult?,
    ): ChunkResult {
        val prompt = WhisperPrompt.build(settings.vocabulary, previous?.text, primer)
        var encoded =
            encoder.encode(audio, options.uploadFormat == PipelineOptions.UploadFormat.flac)
        currentCoroutineContext().ensureActive()
        val seconds = audio.size / AudioEncoder.sampleRate
        suspend fun upload(language: String?): Transcription {
            currentCoroutineContext().ensureActive()
            uploads.incrementAndGet()
            return client.transcribe(encoded, settings.transcriptionModel, language, prompt, seconds) {
                bytes.addAndGet(it)
            }
        }
        suspend fun send(language: String?): Transcription = try { upload(language) }
        catch (failure: GroqFailure) {
            // A manufacturer codec may emit FLAC the server cannot decode. Keep model,
            // language, prompt and PCM identical; never repeat this fallback for a WAV.
            if (!encoded.isFLAC || failure.status != 400 || failure.modelMissing ||
                failure.code !in setOf("invalid_audio", "invalid_audio_file", "invalid_audio_format", "audio_decode_error", "invalid_request_error", "http")) throw failure
            currentCoroutineContext().ensureActive()
            encoded = encoder.encode(audio, preferFLAC = false)
            upload(language)
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
        val expected = LanguageGuard.expected(previousLanguage ?: previousPieceLanguage, primary)
        val first = try { send(null) } catch (f: GroqFailure) {
            return ChunkResult(failure = f)
        }
        val detected = GroqModels.languageCode(first.language)
        var result = first
        var chosenLanguage = detected
        var source = LanguageSource.auto
        if (LanguageGuard.needsCheck(expected, detected, users, spoken)) {
            val checked = try { send(expected) } catch (error: Throwable) {
                currentCoroutineContext().ensureActive()
                error.asGroqFailure()
                null
            }
            if (LanguageGuard.chooseExpected(first, checked)) {
                result = checkNotNull(checked)
                chosenLanguage = expected
                source = LanguageSource.checkedExpected
            } else {
                source = if (checked == null) LanguageSource.checkFailed else LanguageSource.checkedDetected
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
        return ChunkResult(
            text,
            segments,
            chosenLanguage ?: detectLanguage(text, detector),
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
                            } catch (error: Throwable) {
                                val failure = error.asGroqFailure()
                                synchronized(lock) {
                                    lastFailed = true
                                    notifyState(DictationState.failed)
                                }
                                DictationOutcome(error = failure.dictationError,
                                    errorMessage = failure.germanMessage)
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
            // The deferred belongs to the session, not this waiter (like Swift's Task).
            currentCoroutineContext().ensureActive()
            synchronized(lock) {
                lastOutcome ?: if (cancelled) DictationOutcome(error = DictationError.cancelled)
                else DictationOutcome(error = DictationError.network, errorMessage = GroqFailure().germanMessage)
            }
        } catch (error: Throwable) {
            val failure = error.asGroqFailure()
            DictationOutcome(error = failure.dictationError, errorMessage = failure.germanMessage)
        }
    }

    fun releaseAudio() =
        synchronized(lock) {
            if (!finished || finishing) return@synchronized
            audioReleased = true
            samples.clear()
            plan = null
        }

    fun cancel() {
        synchronized(lock) {
            if (cancelled) return
            if (lastOutcome == null || lastFailed) {
                cancelled = true
                finished = true
                chunkingStopped = true
                notifyState(DictationState.cancelled)
            }
            // Successful completion remains terminal; disposal only releases its resources.
            samples.clear()
            plan = null
            audioReleased = true
            notifications.close()
        }
        // Cancelling HTTP may invoke transport hooks. Never do this under the recording lock.
        scope.cancel()
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
                if (!failed) notifications.close()
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
            val result = awaitChunk(chunk.task)
            synchronized(lock) { chunk.result = result }
        }
        currentCoroutineContext().ensureActive()
        val pieces =
            synchronized(lock) { plan ?: makePlan(audio, measured).also { plan = it } }
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

    private fun hasQuietVoice(audio: ShortArray, start: Int): Boolean {
        var run = 0
        val n = VoiceActivityDetector.frameLength
        for (offset in start until audio.size step n) {
            val frame = VoiceActivityDetector.analyze(
                FloatArray(minOf(n, audio.size - offset)) { audio[offset + it] / 32768f }, -100.0)
            run = if (frame.periodicity >= VoiceActivityDetector.voicedPeriodicity) run + 1 else 0
            if (run >= VoiceActivityDetector.minRunFrames) return true
        }
        return false
    }

    private fun makePlan(
        audio: ShortArray,
        measured: VoiceActivityDetector,
    ): MutableList<PlanPiece> {
        val sampleCount = audio.size
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
            // Recheck quiet voiced runs below the normal VAD energy gate.
            // Stationary noise and isolated clicks still do not trigger an upload.
            if (chunks.isEmpty() || pendingBefore || measured.hasAnyActivity(tail) ||
                hasQuietVoice(audio, tailStart))
                addPending(tailStart, sampleCount)
        }
        val bounded = if (options.removeLongSilence) pieces.flatMap { piece ->
            if (piece.result != null) listOf(piece)
            else LongSilence.ranges(measured, piece.start, piece.end).map { PlanPiece(it.first, it.last + 1) }
        } else pieces
        return bounded.flatMap { split(it, measured) }.toMutableList()
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
