package com.paply.android.dictation

import android.content.Context
import android.os.LocaleList
import com.paply.android.AudioCapture
import com.paply.android.Diag
import com.paply.android.history.*
import com.paply.android.settings.*
import com.paply.core.*
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Work outlives an editor or Activity. No microphone is owned by this process scope. */
object DictationRuntime {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val busy = ConcurrentHashMap.newKeySet<String>()
    val isBusy: Boolean get() = busy.isNotEmpty()
    internal fun activeIDs(): Set<String> = busy.toSet()
    internal fun sessionStarted(id: String) { busy.add(id) }
    internal fun sessionEnded(id: String) { busy.remove(id) }
    private var network: AndroidReachability? = null
    private var recovery: Job? = null
    @Synchronized private fun reachability(context: Context) = network ?: AndroidReachability(context).also { network = it }

    suspend fun pipeline(context: Context, state: (DictationStatus) -> Unit = {}): DictationPipeline = withContext(Dispatchers.IO) {
        recovery?.join()
        val prefs = SettingsRepository.get(context).snapshot()
        val history = HistoryStore.get(context)
        history.reload()
        val locales = LocaleList.getDefault()
        DictationPipeline(DictationConfiguration(
            keyProvider = { KeyVault(context).read().orEmpty() }, primaryLanguage = prefs.mainLanguage,
            spokenLanguages = prefs.languages, vocabulary = prefs.vocabulary,
            transcriptionModel = prefs.transcriptionModel, chunkedUpload = prefs.chunkUpload,
            deviceLanguages = (0 until locales.size()).map { locales[it].toLanguageTag() },
        ), options = PipelineOptions(polish = prefs.polish), recentRawDictations = history.recentRawDictations(), encoder = AndroidAudioEncoding(),
            detector = AndroidLanguageDetector(context), clock = AndroidPaplyClock,
            reachability = reachability(context), diagnostic = Diag::event, onState = state)
    }

    fun retry(context: Context, entry: HistoryEntry, completed: (HistoryEntry) -> Unit = {}): Job {
        val owns = busy.add(entry.id)
        val app = context.applicationContext
        return scope.launch(start = CoroutineStart.UNDISPATCHED) {
            var pipeline: DictationPipeline? = null
            val store = HistoryStore.get(app)
            var current = entry
            var result = entry
            try {
                store.reload()
                store.expireAudio(protectedIDs = if (owns) activeIDs() - entry.id else activeIDs())
                val found = store.entries.value.firstOrNull { it.id == entry.id }
                if (found == null) {
                    result = entry.copy(status = HistoryStatus.FAILED, audioFile = null,
                        error = "Eintrag wurde gelöscht.", failure = HistoryFailure.AUDIO_MISSING)
                    return@launch
                }
                current = found; result = current
                if (!owns || current.status != HistoryStatus.FAILED) return@launch
                val file = retainedAudio(app, current.audioFile)
                if (file?.isFile != true) {
                    result = current.copy(status = HistoryStatus.FAILED, audioFile = null,
                        error = HistoryFailure.AUDIO_MISSING.message, failure = HistoryFailure.AUDIO_MISSING)
                    store.updateIfPresent(result)
                    return@launch
                }
                if (!store.updateIfPresent(current.copy(status = HistoryStatus.PENDING, error = null, failure = null))) return@launch
                pipeline = pipeline(app)
                val active = pipeline
                withContext(Dispatchers.IO) { readPcm(file) { ensureActive(); active.append(it) } }
                val outcome = active.finish()
                result = try { persist(app, current, outcome, HistoryStatus.OK) }
                catch (e: Exception) {
                    if (e is CancellationException || outcome.text.isBlank()) throw e
                    rescueText(current, outcome, e)
                }
                Diag.event("dictation.retry status=${result.status}")
            } catch (e: CancellationException) {
                pipeline?.cancel() // Stop HTTP before waiting for the durable retry-state write.
                if (owns) {
                    result = current.copy(status = HistoryStatus.FAILED,
                        error = HistoryFailure.CANCELLED.message, failure = HistoryFailure.CANCELLED)
                    withContext(NonCancellable) { runCatching { store.updateIfPresent(result) } }
                }
                throw e
            } catch (e: Exception) {
                val kind = if (e is java.io.IOException) ImePolicy.failure(e) else HistoryFailure.PROCESSING
                result = current.copy(status = HistoryStatus.FAILED, error = kind.message, failure = kind)
                runCatching { store.updateIfPresent(result) }
            } finally {
                pipeline?.close(); pipeline?.releaseAudio()
                if (owns) busy.remove(entry.id)
                withContext(NonCancellable + Dispatchers.Main.immediate) {
                    runCatching { completed(result) }.onFailure { Diag.event("dictation.retry.callback.failed") }
                }
            }
        }
    }

    internal fun rescueText(entry: HistoryEntry, outcome: DictationOutcome, cause: Throwable) = entry.copy(
        raw = outcome.raw.ifBlank { outcome.text }, polished = outcome.polished.orEmpty(),
        status = HistoryStatus.PENDING, failure = ImePolicy.storageFailure(cause),
        error = "Text konnte nicht im Verlauf gespeichert werden.",
    )

    internal suspend fun persist(context: Context, entry: HistoryEntry, outcome: DictationOutcome,
        success: HistoryStatus = HistoryStatus.PENDING): HistoryEntry {
        val store = HistoryStore.get(context)
        val result = if (outcome.text.isNotBlank()) entry.copy(
            polished = outcome.polished.orEmpty(), raw = outcome.raw.ifBlank { outcome.text },
            language = outcome.language, status = success, audioFile = null,
            failure = null,
            error = if (outcome.polishFailure != null || outcome.polishRejectionCode != null) "Ohne Polieren gespeichert." else null,
        ) else entry.copy(status = HistoryStatus.FAILED,
            error = outcome.errorMessage ?: "Nichts verstanden. Bitte erneut versuchen.",
            failure = when (outcome.error) {
                DictationError.unauthorized -> HistoryFailure.KEY
                DictationError.audioUnavailable -> HistoryFailure.AUDIO_MISSING
                else -> HistoryFailure.PROCESSING
            })
        // Atomic durable text FIRST. Only then is audio disposable.
        if (!store.updateIfPresent(result)) {
            withContext(Dispatchers.IO) { retainedAudio(context, entry.audioFile)?.delete() }
            throw CancellationException("dictation-deleted")
        }
        if (result.text.isNotBlank()) withContext(Dispatchers.IO) { retainedAudio(context, entry.audioFile)?.delete() }
        Diag.event("dictation.saved status=${result.status} chars=${result.text.length} audio=${result.audioFile != null} chunks=${outcome.timings.chunkCount} bytes=${outcome.timings.uploadedBytes} totalMs=${outcome.timings.totalMs?.toLong()} languages=${outcome.languages.size} checkedExpected=${outcome.languageSources.count { it == "checked-expected" }} checkedDetected=${outcome.languageSources.count { it == "checked-detected" }} checkFailed=${outcome.languageSources.count { it == "check-failed" }}")
        return result
    }

    internal fun retainedAudio(context: Context, path: String?): File? {
        if (path == null) return null
        val dir = File(context.filesDir, "dictations").canonicalFile
        return File(path).canonicalFile.takeIf { it.parentFile == dir && it.extension == "wav" }
    }

    /** WavWriter's fixed PCM16 format, validated before append; no arbitrary decoder or huge read. */
    internal fun readPcm(file: File, append: (ShortArray) -> Unit) {
        RandomAccessFile(file, "r").use { input ->
            val header = ByteArray(44); input.readFully(header)
            val b = java.nio.ByteBuffer.wrap(header).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            require(String(header, 0, 4) == "RIFF" && String(header, 8, 4) == "WAVE" && String(header, 36, 4) == "data")
            require(b.getShort(20).toInt() == 1 && b.getShort(22).toInt() == 1 && b.getInt(24) == 16000 && b.getShort(34).toInt() == 16)
            var left = b.getInt(40).toLong()
            require(left > 0 && left % 2L == 0L && left <= input.length() - 44)
            val bytes = ByteArray(6400)
            while (left > 0) {
                val n = minOf(left, bytes.size.toLong()).toInt(); input.readFully(bytes, 0, n)
                val buffer = java.nio.ByteBuffer.wrap(bytes, 0, n).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                append(ShortArray(n / 2) { buffer.short }); left -= n
            }
        }
    }

    /** A process-dead, confirmed recording is retryable, never automatically uploaded. */
    fun recover(context: Context) {
        recovery = scope.launch(Dispatchers.IO) {
        val store = HistoryStore.get(context)
        runCatching {
            store.reload()
            store.entries.value.filter { it.status == HistoryStatus.PENDING && it.audioFile != null }.forEach {
                store.add(it.copy(status = HistoryStatus.FAILED, error = "Verarbeitung unterbrochen. Erneut versuchen."))
            }
            store.expireAudio(protectedIDs = activeIDs())
            val referenced = store.entries.value.mapNotNull { it.audioFile }.toSet()
            File(context.filesDir, "dictations").listFiles()?.filter { it.path !in referenced }?.forEach { it.delete() }
        }.onFailure { Diag.event("dictation.recovery.failed") }
        }
    }
}

data class SessionState(val phase: String = "recording", val entry: HistoryEntry? = null, val error: String? = null)

class DictationSession private constructor(private val app: Context, val pipeline: DictationPipeline, val file: File) {
    private val mutable = MutableStateFlow(SessionState())
    val state = mutable.asStateFlow()
    val recording = AudioCapture(app, file, maxMs = ImePolicy.MAX_MS, onSamples = pipeline::append)
    private var work: Job? = null
    private var warm: Job? = null
    private val id = UUID.randomUUID().toString()
    private val createdAt = System.currentTimeMillis()
    private var discarded = false
    private var started = false
    var limitReached = false; private set
    var finishTapNs = 0L; private set
    val speechDetected get() = pipeline.speechDetected
    fun start() {
        recording.start()
        DictationRuntime.sessionStarted(id)
        started = true
        // Started alongside capture, gated on actual speech: switching past Paply costs no request.
        warm = DictationRuntime.scope.launch(Dispatchers.IO) {
            while (!pipeline.speechDetected) delay(40)
            runCatching { GroqConnection.prewarm(KeyVault(app).read().orEmpty()) }
        }
        DictationRuntime.scope.launch {
            val result = recording.awaitEnd()
            if (mutable.value.phase == "recording" && !discarded) {
                limitReached = android.os.SystemClock.elapsedRealtime() - recording.startedAt >= ImePolicy.MAX_MS
                if (speechDetected) finish() else discard()
                if (result.error != null) Diag.event("ime.audio.interrupted")
            }
        }
    }
    fun finish() {
        if (work != null || discarded) return
        finishTapNs = AndroidPaplyClock.monotonicNanos()
        mutable.value = SessionState("working")
        work = DictationRuntime.scope.launch {
            val audio = recording.finish()
            warm?.cancel()
            if (!speechDetected) { discard(); return@launch }
            var entry = HistoryEntry(id, createdAt, durationMs = audio.durationMs,
                status = HistoryStatus.PENDING, audioFile = file.path)
            try {
                // Start the durable PENDING write beside upload; only final audio deletion waits for it.
                val (result, pending) = supervisorScope {
                    val saved = async { runCatching { HistoryStore.get(app).add(entry) } }
                    val outcome = pipeline.finish()
                    outcome to saved.await()
                }
                if (discarded) return@launch
                // The core can reject a false-positive VAD/noise burst after its final check.
                // Silence is not a failed dictation and must not leave audio/history behind.
                if (result.noSpeech) { discard(); return@launch }
                if (result.text.isNotBlank() && pending.isFailure) {
                    // Disk failure must not swallow speech already transcribed from memory.
                    entry = DictationRuntime.rescueText(entry, result, pending.exceptionOrNull()!!)
                } else {
                    pending.getOrThrow()
                    try { entry = DictationRuntime.persist(app, entry, result) }
                    catch (e: Exception) {
                        if (e is CancellationException || result.text.isBlank()) throw e
                        entry = DictationRuntime.rescueText(entry, result, e)
                    }
                }
                mutable.value = SessionState(if (entry.text.isNotBlank()) "result" else "failed", entry, entry.error)
            } catch (e: CancellationException) {
                mutable.value = SessionState("discarded")
                throw e
            } catch (e: Exception) {
                val kind = if (e is java.io.IOException || e is StorageAccessException) ImePolicy.failure(e) else HistoryFailure.PROCESSING
                entry = entry.copy(status = HistoryStatus.FAILED, error = kind.message, failure = kind)
                runCatching { HistoryStore.get(app).add(entry) }
                mutable.value = SessionState("failed", entry, entry.error)
            } finally { pipeline.close(); pipeline.releaseAudio(); DictationRuntime.sessionEnded(id) }
        }
    }
    fun discard() {
        if (discarded) return
        discarded = true
        recording.requestStop(); warm?.cancel(); pipeline.cancel(); work?.cancel()
        mutable.value = SessionState("discarded")
        DictationRuntime.scope.launch(Dispatchers.IO) {
            runCatching {
                if (started) recording.awaitEnd()
                work?.join() // A cancelled disk write must finish before cleanup, never re-create the entry.
            }
            DictationRuntime.sessionEnded(id)
            pipeline.releaseAudio()
            discardFiles(file, id) { HistoryStore.get(app) }
        }
        Diag.event("ime.discard speech=$speechDetected")
    }
    companion object {
        internal suspend fun discardFiles(file: File, id: String, history: () -> HistoryStore) {
            runCatching { file.delete() }
            runCatching {
                val store = history()
                store.reload()
                if (store.entries.value.any { it.id == id }) store.delete(setOf(id))
            }.onFailure { Diag.event("ime.discard.history.failed") }
        }
        suspend fun prepare(context: Context): DictationSession {
            val app = context.applicationContext
            val pipeline = DictationRuntime.pipeline(app)
            return try {
                val file = withContext(Dispatchers.IO) {
                    val dir = File(app.filesDir, "dictations"); if (!dir.isDirectory && !dir.mkdirs()) throw StorageAccessException()
                    File.createTempFile("dictation-", ".wav", dir)
                }
                DictationSession(app, pipeline, file)
            } catch (e: Exception) { pipeline.close(); throw e }
        }
    }
}
