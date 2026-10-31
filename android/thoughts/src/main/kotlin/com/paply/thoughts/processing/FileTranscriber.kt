package com.paply.thoughts.processing

import com.paply.core.*
import com.paply.thoughts.model.TextForm
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Path
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import okhttp3.HttpUrl

enum class TranscriptionFailure {
    unauthorized,
    rateLimited,
    network,
    server,
    invalidResponse,
    modelMissing,
    rejected,
    unreadableAudio,
    cancelled,
}

sealed interface TranscriptionResult {
    val sentAudioSeconds: Double get() = 0.0
    data class Success(
        val text: String,
        val languages: List<String>,
        val audioSeconds: Double,
        val model: String,
        override val sentAudioSeconds: Double = audioSeconds,
    ) : TranscriptionResult

    data object NoSpeech : TranscriptionResult

    data class Empty(override val sentAudioSeconds: Double) : TranscriptionResult

    data class Failure(val failure: TranscriptionFailure, override val sentAudioSeconds: Double = 0.0) : TranscriptionResult
}

fun interface ThoughtTranscribing {
    suspend fun transcribe(
        audioURL: Path,
        apiKey: String,
        settings: PaplySettings,
    ): TranscriptionResult
}

/**
 * WAV decoding only; an Android m4a decoder can be injected without introducing Android into this
 * JVM module.
 */
class FileTranscriber(
    private val transport: GroqTransport = GroqTransport.shared,
    private val baseURL: HttpUrl = GroqClient.defaultBaseURL,
    private val catalog: ModelCatalog = ModelCatalog.shared,
    private val decoder: ((Path) -> FloatArray?)? = null,
    private val diagnostic: (String) -> Unit = {},
) : ThoughtTranscribing {
    override suspend fun transcribe(
        audioURL: Path,
        apiKey: String,
        settings: PaplySettings,
    ): TranscriptionResult {
        // Production WAV reads are bounded. The optional legacy decoder is only an adapter.
        val input = try {
            if (decoder != null) ArrayPcm(decoder.invoke(audioURL)
                ?: return TranscriptionResult.Failure(TranscriptionFailure.unreadableAudio))
            else WavePcm(audioURL)
        } catch (_: Exception) { return TranscriptionResult.Failure(TranscriptionFailure.unreadableAudio) }
        var sentSeconds = 0.0
        return input.use { pcm ->
            try {
                if (pcm.size == 0) return@use TranscriptionResult.NoSpeech
                // First pass retains VAD measurements, never the recording's PCM.
                val vad = VoiceActivityDetector(analyzeQuietFrames = true)
                var start = 0
                while (start < pcm.size) {
                    currentCoroutineContext().ensureActive()
                    val end = minOf(pcm.size, start + 16000)
                    vad.process(pcm.read(start, end)); start = end
                }
                val ranges = LongSilence.ranges(vad, 0, pcm.size)
                val texts = mutableListOf<String>()
                val languages = linkedSetOf<String>()
                var previousLanguage: String? = null
                for (range in ranges) {
                    start = range.first
                    while (start <= range.last) {
                        currentCoroutineContext().ensureActive()
                        var end = minOf(range.last + 1, start + MAX_PIECE_SAMPLES)
                        if (end < range.last + 1) {
                            // Prefer a quiet frame near the bound; no samples are lost at the seam.
                            val n = VoiceActivityDetector.frameLength
                            val cut = ((end - 5 * 16000) / n until end / n)
                                .minByOrNull { vad.frames[it].dbfs }
                            if (cut != null) end = cut * n
                        }
                        val pipeline = DictationPipeline(
                            settings.copy(chunkedUpload = false),
                            GroqClient(apiKey, baseUrl = baseURL, transport = transport, diagnostic = {
                                if (it == "whisper.request") diagnostic("thought.groq count=1")
                            }), catalog, PipelineOptions(polish = false, removeLongSilence = true),
                            previousPieceLanguage = previousLanguage,
                        )
                        try {
                            var offset = start
                            while (offset < end) {
                                currentCoroutineContext().ensureActive()
                                val next = minOf(end, offset + 16000)
                                pipeline.append(pcm.read(offset, next)); offset = next
                            }
                            val outcome = pipeline.finish()
                            sentSeconds += outcome.timings.sentAudioSeconds
                            if (outcome.error == null && outcome.raw.isNotBlank())
                                outcome.lastPieceLanguage?.let { previousLanguage = it }
                            diagnostic("thought.transcribe.end chunks=${outcome.timings.chunkCount} bytes=${outcome.timings.uploadedBytes}")
                            when (val result = result(outcome, settings.transcriptionModel)) {
                                is TranscriptionResult.Failure -> return@use result.copy(sentAudioSeconds = sentSeconds)
                                is TranscriptionResult.Success -> { texts += result.text; languages += result.languages }
                                TranscriptionResult.NoSpeech, is TranscriptionResult.Empty -> Unit
                            }
                        } finally { pipeline.releaseAudio(); pipeline.close() }
                        start = end
                    }
                }
                if (texts.isEmpty()) emptyResult(sentSeconds)
                else TranscriptionResult.Success(texts.joinToString(" "), languages.toList(), pcm.size / 16000.0, settings.transcriptionModel, sentSeconds)
            } catch (_: CancellationException) {
                TranscriptionResult.Failure(TranscriptionFailure.cancelled, sentSeconds)
            } catch (_: java.io.IOException) {
                TranscriptionResult.Failure(TranscriptionFailure.unreadableAudio, sentSeconds)
            }
        }
    }

    companion object {
        private fun emptyResult(sent: Double): TranscriptionResult =
            if (sent == 0.0) TranscriptionResult.NoSpeech else TranscriptionResult.Empty(sent)

        internal const val MAX_PIECE_SAMPLES = 60 * 16000
        fun result(outcome: DictationOutcome, model: String): TranscriptionResult {
            if (outcome.noSpeech) return emptyResult(outcome.timings.sentAudioSeconds)
            outcome.errorMessage?.let {
                return TranscriptionResult.Failure(classify(it), outcome.timings.sentAudioSeconds)
            }
            val raw = TextForm.trim(outcome.raw)
            if (raw.isEmpty()) return TranscriptionResult.Failure(TranscriptionFailure.cancelled)
            return TranscriptionResult.Success(
                raw,
                outcome.languages,
                outcome.timings.audioSeconds,
                model,
                outcome.timings.sentAudioSeconds,
            )
        }

        fun classify(message: String): TranscriptionFailure {
            listOf(
                    GroqFailure(401) to TranscriptionFailure.unauthorized,
                    GroqFailure(429) to TranscriptionFailure.rateLimited,
                    GroqFailure(413) to TranscriptionFailure.rejected,
                    GroqFailure(404) to TranscriptionFailure.modelMissing,
                    GroqFailure() to TranscriptionFailure.network,
                    GroqFailure(code = "invalid-response") to TranscriptionFailure.invalidResponse,
                    GroqFailure(code = "cancelled") to TranscriptionFailure.cancelled,
                )
                .firstOrNull { it.first.germanMessage == message }
                ?.let {
                    return it.second
                }
            if (message.startsWith(GroqFailure(500).germanMessage.substringBefore('(')))
                return TranscriptionFailure.server
            if (message.startsWith(GroqFailure(400).germanMessage.substringBefore('(')))
                return TranscriptionFailure.rejected
            if (message.contains("nicht mehr verfügbar"))
                return TranscriptionFailure.unreadableAudio
            return TranscriptionFailure.server
        }

        /**
         * RIFF chunk reader: own 16kHz mono PCM16 or IEEE float32 WAV, bounded and never modifies
         * input.
         */
        fun readSamples(url: Path): FloatArray? = runCatching {
            WavePcm(url).use { it.read(0, it.size) }
        }.getOrNull()
    }
}

internal interface FilePcm : AutoCloseable {
    val size: Int
    fun read(start: Int, end: Int): FloatArray
}
private class ArrayPcm(private val samples: FloatArray) : FilePcm {
    override val size get() = samples.size
    override fun read(start: Int, end: Int) = samples.copyOfRange(start, end)
    override fun close() {}
}

/** Seekable RIFF parser. Chunk lengths are validated before allocating only the requested window. */
internal class WavePcm(url: Path) : FilePcm {
    private val file = java.io.RandomAccessFile(url.toFile(), "r")
    private var dataStart = 0L
    private var format = 0
    private var width = 0
    override val size: Int
    init {
        try {
            fun bytes(count: Int) = ByteArray(count).also(file::readFully)
            val header = bytes(12)
            require(String(header, 0, 4, Charsets.US_ASCII) == "RIFF" && String(header, 8, 4, Charsets.US_ASCII) == "WAVE")
            var dataSize = -1L
            var valid = false
            while (file.filePointer + 8 <= file.length()) {
                val chunk = bytes(8)
                val length = ByteBuffer.wrap(chunk).order(ByteOrder.LITTLE_ENDIAN).getInt(4).toLong() and 0xffffffffL
                val begin = file.filePointer
                require(length <= file.length() - begin)
                when (String(chunk, 0, 4, Charsets.US_ASCII)) {
                    "fmt " -> {
                        require(length >= 16)
                        val f = ByteBuffer.wrap(bytes(16)).order(ByteOrder.LITTLE_ENDIAN)
                        format = f.getShort(0).toInt()
                        val bits = f.getShort(14).toInt()
                        valid = f.getShort(2).toInt() == 1 && f.getInt(4) == 16000 &&
                            (format == 1 && bits == 16 || format == 3 && bits == 32)
                        width = bits / 8
                    }
                    "data" -> { dataStart = begin; dataSize = length }
                }
                file.seek(begin + length + length % 2)
            }
            require(valid && dataSize >= 0 && dataSize % width == 0L && dataSize / width <= Int.MAX_VALUE)
            size = (dataSize / width).toInt()
        } catch (e: Exception) { file.close(); throw e }
    }
    override fun read(start: Int, end: Int): FloatArray {
        require(start >= 0 && end >= start && end <= size)
        file.seek(dataStart + start.toLong() * width)
        val bytes = ByteArray(Math.multiplyExact(end - start, width))
        file.readFully(bytes)
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return FloatArray(end - start) {
            if (format == 1) b.short / 32768f else b.float.takeIf { it.isFinite() } ?: 0f
        }
    }
    override fun close() = file.close()
}
