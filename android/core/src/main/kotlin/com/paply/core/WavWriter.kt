package com.paply.core

import java.io.File
import java.io.RandomAccessFile

/** 16 kHz, mono PCM16. One owning recording thread writes and closes the file. */
@Deprecated(
    "Use AudioEncoder.wav for core uploads; app recording persistence will move to its audio adapter",
)
class WavWriter(file: File) : AutoCloseable {
    private val output = RandomAccessFile(file, "rw")
    private var bytes = 0

    init {
        output.setLength(0)
        output.write(ByteArray(44))
    }

    fun append(samples: ShortArray, count: Int) {
        val data = ByteArray(count * 2)
        for (i in 0 until count) {
            data[i * 2] = samples[i].toByte()
            data[i * 2 + 1] = (samples[i].toInt() shr 8).toByte()
        }
        output.write(data)
        bytes += data.size
    }

    override fun close() {
        try {
            output.seek(0)
            fun le(value: Int, width: Int) {
                repeat(width) { output.write(value ushr (8 * it) and 255) }
            }
            output.writeBytes("RIFF")
            le(bytes + 36, 4)
            output.writeBytes("WAVEfmt ")
            le(16, 4)
            le(1, 2)
            le(1, 2)
            le(16000, 4)
            le(32000, 4)
            le(2, 2)
            le(16, 2)
            output.writeBytes("data")
            le(bytes, 4)
            output.fd.sync()
        } finally {
            output.close()
        }
    }
}

/** Trim only quiet edges of our own PCM WAV, keeping half a second of context at each end. */
@Deprecated(
    "Use DictationPipeline VAD and SilenceFilter; retained only for Phase-0 recording callers",
)
fun trimQuietEdges(file: File, firstVoicedFrame: Long, lastVoicedFrame: Long): Long {
    require(firstVoicedFrame >= 0 && lastVoicedFrame > firstVoicedFrame)
    return RandomAccessFile(file, "rw").use { wav ->
        val frames = (wav.length() - 44) / 2
        val start = (firstVoicedFrame - 8000).coerceAtLeast(0)
        val end = (lastVoicedFrame + 8000).coerceAtMost(frames)
        require(end >= start)
        val bytes = (end - start) * 2
        val buffer = ByteArray(32768)
        var copied = 0L
        while (copied < bytes) {
            val count = minOf(buffer.size.toLong(), bytes - copied).toInt()
            wav.seek(44 + start * 2 + copied)
            wav.readFully(buffer, 0, count)
            wav.seek(44 + copied)
            wav.write(buffer, 0, count)
            copied += count
        }
        fun size(offset: Long, value: Long) {
            wav.seek(offset)
            repeat(4) { wav.write((value ushr (8 * it)).toInt() and 255) }
        }
        size(4, bytes + 36)
        size(40, bytes)
        wav.setLength(44 + bytes)
        wav.fd.sync()
        end - start
    }
}
