package com.paply.thoughts.processing

import com.paply.core.*
import com.paply.thoughts.model.TextForm
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Path
import kotlinx.coroutines.CancellationException
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
    data class Success(
        val text: String,
        val languages: List<String>,
        val audioSeconds: Double,
        val model: String,
    ) : TranscriptionResult

    data object NoSpeech : TranscriptionResult

    data class Failure(val failure: TranscriptionFailure) : TranscriptionResult
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
    private val decoder: (Path) -> FloatArray? = ::readSamples,
) : ThoughtTranscribing {
    override suspend fun transcribe(
        audioURL: Path,
        apiKey: String,
        settings: PaplySettings,
    ): TranscriptionResult {
        val samples =
            decoder(audioURL)
                ?: return TranscriptionResult.Failure(TranscriptionFailure.unreadableAudio)
        if (samples.isEmpty()) return TranscriptionResult.NoSpeech
        val pipeline =
            DictationPipeline(
                settings.copy(chunkedUpload = false),
                GroqClient(apiKey, baseUrl = baseURL, transport = transport),
                catalog,
                PipelineOptions(polish = false),
            )
        return try {
            var start = 0
            while (start < samples.size) {
                val end = minOf(samples.size, start + 16000)
                pipeline.append(samples.copyOfRange(start, end))
                start = end
            }
            result(pipeline.finish(), settings.transcriptionModel)
        } catch (_: CancellationException) {
            TranscriptionResult.Failure(TranscriptionFailure.cancelled)
        } finally {
            pipeline.releaseAudio()
            pipeline.close()
        }
    }

    companion object {
        fun result(outcome: DictationOutcome, model: String): TranscriptionResult {
            if (outcome.noSpeech) return TranscriptionResult.NoSpeech
            outcome.errorMessage?.let {
                return TranscriptionResult.Failure(classify(it))
            }
            val raw = TextForm.trim(outcome.raw)
            if (raw.isEmpty()) return TranscriptionResult.Failure(TranscriptionFailure.cancelled)
            return TranscriptionResult.Success(
                raw,
                outcome.languages,
                outcome.timings.audioSeconds,
                model,
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
            val bytes = java.nio.file.Files.readAllBytes(url)
            val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            fun tag(at: Int) = String(bytes, at, 4, Charsets.US_ASCII)
            if (bytes.size < 12 || tag(0) != "RIFF" || tag(8) != "WAVE") return null
            var format = 0
            var bits = 0
            var validFormat = false
            var data: Pair<Int, Int>? = null
            var p = 12
            while (p + 8 <= bytes.size) {
                val size = b.getInt(p + 4).toLong() and 0xffffffffL
                val begin = p + 8
                if (size > bytes.size - begin) return null
                when (tag(p)) {
                    "fmt " -> {
                        if (size < 16) return null
                        format = b.getShort(begin).toInt()
                        bits = b.getShort(begin + 14).toInt()
                        validFormat =
                            b.getShort(begin + 2).toInt() == 1 &&
                                b.getInt(begin + 4) == 16000 &&
                                ((format == 1 && bits == 16) || (format == 3 && bits == 32))
                    }
                    "data" -> data = begin to size.toInt()
                }
                p = (begin + size + (size % 2)).toInt()
            }
            if (!validFormat) return null
            val (begin, size) = data ?: return null
            val width = bits / 8
            if (size % width != 0) return null
            FloatArray(size / width) { i ->
                if (format == 1) b.getShort(begin + i * 2) / 32768f
                else b.getFloat(begin + i * 4).takeIf { it.isFinite() } ?: 0f
            }
        }
            .getOrNull()
    }
}
