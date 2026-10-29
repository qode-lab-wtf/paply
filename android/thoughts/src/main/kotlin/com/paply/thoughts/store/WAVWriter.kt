package com.paply.thoughts.store

import com.paply.core.AudioEncoder
import java.io.DataInputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.Executors

/** Serial writer; append only copies and enqueues. The microphone thread never waits on disk. */
class WAVWriter(val url: Path) {
    private val queue = Executors.newSingleThreadExecutor { r ->
        Thread(r, "paply-thought-wav").apply { isDaemon = true }
    }
    private val handle = RandomAccessFile(url.toFile(), "rw")
    @Volatile private var dataBytes = 0
    @Volatile private var failed = false
    private var unsyncedSamples = 0
    private var closed = false
    private val lifecycle = Any()

    init {
        handle.setLength(0)
        handle.write(header(0))
    }

    fun append(samples: FloatArray) = append(AudioEncoder.int16(samples))

    fun append(samples: ShortArray) {
        if (samples.isEmpty()) return
        val copy = samples.copyOf()
        synchronized(lifecycle) {
            if (closed) return
            queue.execute {
                if (!failed)
                    try {
                        val pcm = copy
                        val data = ByteBuffer.allocate(pcm.size * 2).order(ByteOrder.LITTLE_ENDIAN)
                        pcm.forEach { data.putShort(it) }
                        handle.write(data.array())
                        dataBytes += data.capacity()
                        unsyncedSamples += pcm.size
                        if (unsyncedSamples >= syncInterval) {
                            unsyncedSamples = 0
                            patchHeader(handle, dataBytes)
                            handle.fd.sync()
                        }
                    } catch (_: IOException) {
                        failed = true
                        dataBytes =
                            runCatching {
                                    (handle.length() - headerSize).coerceAtLeast(0).toInt().let {
                                        it - it % 2
                                    }
                                }
                                .getOrDefault(dataBytes)
                        runCatching {
                            patchHeader(handle, dataBytes)
                            handle.fd.sync()
                        }
                    }
            }
        }
    }

    fun close(): Int =
        synchronized(lifecycle) {
            if (!closed) {
                closed = true
                queue
                    .submit {
                        try {
                            patchHeader(handle, dataBytes)
                            handle.fd.sync()
                        } catch (_: IOException) {
                            failed = true
                        } finally {
                            runCatching { handle.close() }
                        }
                    }
                    .get()
                queue.shutdown()
            }
            durationMs(dataBytes)
        }

    fun waitForPendingWrites() =
        synchronized(lifecycle) {
            if (!closed) queue.submit {}.get()
            Unit
        }

    val durationMs
        get() = durationMs(dataBytes)

    val hasFailed
        get() = failed

    class WAVError(val code: Code) : IOException(code.name) {
        enum class Code {
            create,
            notWAV,
        }
    }

    companion object {
        const val sampleRate = 16_000
        const val headerSize = 44
        const val syncInterval = 2 * sampleRate

        fun durationMs(dataBytes: Int) = (dataBytes.toLong() / 2 * 1000 / sampleRate).toInt()

        fun header(dataBytes: Int): ByteArray =
            AudioEncoder.wav(shortArrayOf()).also {
                ByteBuffer.wrap(it)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .putInt(4, 36 + dataBytes)
                    .putInt(40, dataBytes)
            }

        private fun patchHeader(handle: RandomAccessFile, dataBytes: Int) {
            handle.seek(0)
            handle.write(header(dataBytes))
            handle.seek(handle.length())
        }

        fun repair(url: Path): Int =
            RandomAccessFile(url.toFile(), "rw").use { handle ->
                val size = handle.length()
                if (size < headerSize) {
                    handle.setLength(0)
                    handle.write(header(0))
                    handle.fd.sync()
                    return 0
                }
                val head = ByteArray(12)
                handle.seek(0)
                handle.readFully(head)
                if (
                    String(head, 0, 4, Charsets.US_ASCII) != "RIFF" ||
                        String(head, 8, 4, Charsets.US_ASCII) != "WAVE"
                )
                    throw WAVError(WAVError.Code.notWAV)
                val bytes = (size - headerSize).toInt().let { it - it % 2 }
                handle.setLength((headerSize + bytes).toLong())
                patchHeader(handle, bytes)
                handle.fd.sync()
                durationMs(bytes)
            }

        fun headerDurationMs(url: Path): Int? =
            try {
                Files.newInputStream(url).use { input ->
                    val head = ByteArray(headerSize)
                    DataInputStream(input).readFully(head)
                    if (String(head, 0, 4, Charsets.US_ASCII) != "RIFF")
                        null
                    else durationMs(ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN).getInt(40))
                }
            } catch (_: IOException) {
                null
            }
    }
}
