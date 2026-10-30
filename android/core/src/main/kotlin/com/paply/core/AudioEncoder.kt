package com.paply.core

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Android supplies lossless mono PCM16/16k FLAC (MediaCodec), returning null on unsupported/failed
 * encoding. Implementations must clean temporary files on every exit. Core always falls back to
 * WAV.
 */
fun interface FlacEncoder {
    fun encode(samples: ShortArray): ByteArray?
}

fun interface AudioEncoding {
    fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded
}

class DefaultAudioEncoding(
    private val flac: FlacEncoder? = null,
    private val clock: PaplyClock = SystemPaplyClock,
) : AudioEncoding {
    override fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded {
        val start = clock.monotonicNanos()
        val compressed =
            if (preferFLAC && samples.isNotEmpty())
                try {
                    flac?.encode(samples)
                } catch (_: Exception) {
                    null
                }
            else null
        val valid = compressed?.takeIf {
            it.size > 42 && it.copyOfRange(0, 4).contentEquals("fLaC".toByteArray())
        }
        val data = valid ?: AudioEncoder.wav(samples)
        return AudioEncoder.Encoded(
            data,
            if (valid != null) "audio.flac" else "audio.wav",
            if (valid != null) "audio/flac" else "audio/wav",
            (clock.monotonicNanos() - start) / 1e6,
        )
    }
}

object AudioEncoder {
    const val sampleRate = 16_000.0

    data class Encoded(
        val data: ByteArray,
        val fileName: String,
        val mimeType: String,
        val encodeMs: Double = 0.0,
    ) {
        val isFLAC
            get() = mimeType == "audio/flac"
    }

    fun encode(samples: ShortArray, preferFLAC: Boolean = true) =
        DefaultAudioEncoding().encode(samples, preferFLAC)

    fun wav(samples: ShortArray): ByteArray {
        val bytes = samples.size * 2
        val b = ByteBuffer.allocate(44 + bytes).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray())
        b.putInt(36 + bytes)
        b.put("WAVEfmt ".toByteArray())
        b.putInt(16)
        b.putShort(1)
        b.putShort(1)
        b.putInt(16000)
        b.putInt(32000)
        b.putShort(2)
        b.putShort(16)
        b.put("data".toByteArray())
        b.putInt(bytes)
        samples.forEach(b::putShort)
        return b.array()
    }

    fun int16(samples: FloatArray) =
        ShortArray(samples.size) {
            val clamped = (if (samples[it].isFinite()) samples[it] else 0f).coerceIn(-1f, 1f)
            (if (clamped < 0) clamped * 32768 else clamped * 32767).toInt().toShort()
        }

    fun floats(samples: ShortArray) = FloatArray(samples.size) { samples[it] / 32768f }
}
