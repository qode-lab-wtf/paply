package com.paply.android.dictation

import android.content.Context
import android.media.MediaCodec
import android.media.MediaFormat
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.view.textclassifier.TextClassificationManager
import android.view.textclassifier.TextLanguage
import com.paply.android.Diag
import com.paply.core.*
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import kotlinx.coroutines.delay

object AndroidPaplyClock : PaplyClock {
    override fun nowMillis() = System.currentTimeMillis()
    override fun monotonicNanos() = SystemClock.elapsedRealtimeNanos()
    override suspend fun sleep(seconds: Double) = delay(kotlin.math.ceil(seconds.coerceAtLeast(0.0) * 1000).toLong())
}

/** Platform on-device classifier; no Play Services dependency and no app network request. */
class AndroidLanguageDetector(context: Context) : LanguageDetector {
    private val manager = context.applicationContext.getSystemService(TextClassificationManager::class.java)
    override fun detect(text: String): String? = try {
        val result = manager.textClassifier.detectLanguage(TextLanguage.Request.Builder(text).build())
        if (result.localeHypothesisCount == 0) null else result.getLocale(0).language
    } catch (_: Exception) { null }
}

/** One callback for the process, never one per recording. HTTP remains authoritative. */
class AndroidReachability(context: Context) : NetworkReachability {
    private val manager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
    init {
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = changed()
            override fun onLost(network: Network) = changed()
            private fun changed() { GroqConnection.reset(); Diag.event("network.changed") }
        })
    }
    override fun isReachable(): Boolean = manager.getNetworkCapabilities(manager.activeNetwork)
        ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ?: false
}

/** MediaCodec emits FLAC metadata as codec-config/csd-0, followed by FLAC frames (no muxer). */
class AndroidFlacEncoder : FlacEncoder {
    override fun encode(samples: ShortArray): ByteArray? {
        var codec: MediaCodec? = null
        return try {
            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_FLAC)
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_FLAC, 16000, 1)
            format.setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 5)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val frames = ByteArrayOutputStream()
            var header: ByteArray? = null
            var offset = 0
            var inputEnded = false
            var outputEnded = false
            var lastProgress = SystemClock.elapsedRealtime()
            val info = MediaCodec.BufferInfo()
            while (!outputEnded) {
                check(SystemClock.elapsedRealtime() - lastProgress < 5000) { "flac-stalled" }
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val buffer = requireNotNull(codec.getInputBuffer(index)).order(ByteOrder.LITTLE_ENDIAN)
                        buffer.clear()
                        val count = minOf(buffer.remaining() / 2, samples.size - offset)
                        for (i in 0 until count) buffer.putShort(samples[offset + i])
                        val end = offset + count == samples.size
                        codec.queueInputBuffer(index, 0, count * 2, offset * 1_000_000L / 16000,
                            if (end) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                        offset += count; inputEnded = end; lastProgress = SystemClock.elapsedRealtime()
                    }
                }
                when (val index = codec.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        codec.outputFormat.getByteBuffer("csd-0")?.duplicate()?.let { b ->
                            header = ByteArray(b.remaining()).also { b.get(it) }
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                    else -> if (index >= 0) {
                        try {
                            val buffer = requireNotNull(codec.getOutputBuffer(index)).duplicate()
                            buffer.position(info.offset); buffer.limit(info.offset + info.size)
                            val data = ByteArray(info.size).also { buffer.get(it) }
                            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                                if (data.isNotEmpty()) header = data
                            } else frames.write(data)
                            outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            lastProgress = SystemClock.elapsedRealtime()
                        } finally { codec.releaseOutputBuffer(index, false) }
                    }
                }
            }
            val metadata = requireNotNull(header).copyOf()
            // The documented Android CSD starts with fLaC + mandatory 34-byte STREAMINFO.
            require(metadata.size >= 42 && metadata.copyOfRange(0, 4).contentEquals("fLaC".toByteArray()))
            require(metadata[4].toInt() and 0x7f == 0 && metadata[5].toInt() == 0 && metadata[6].toInt() == 0 && metadata[7].toInt() == 34)
            // Streaming encoders cannot seek back: supply the known total sample count. MD5=0
            // is explicitly allowed for an unknown signature. Retain any further metadata blocks.
            var packed = 0L
            for (i in 18..25) packed = (packed shl 8) or (metadata[i].toLong() and 255)
            packed = (packed and (-1L shl 36)) or samples.size.toLong()
            for (i in 25 downTo 18) { metadata[i] = packed.toByte(); packed = packed ushr 8 }
            if (metadata.size == 42) metadata[4] = 0x80.toByte()
            require(frames.size() > 0)
            metadata + frames.toByteArray()
        } catch (_: Exception) {
            Diag.event("audio.flac.fallback")
            null
        } finally {
            codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
        }
    }
}

class AndroidAudioEncoding : AudioEncoding {
    private val delegate = DefaultAudioEncoding(AndroidFlacEncoder(), AndroidPaplyClock)
    override fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded = delegate.encode(samples, preferFLAC).also {
        Diag.event("audio.encode flac=${it.isFLAC} bytes=${it.data.size} wavBytes=${samples.size * 2 + 44} ms=${it.encodeMs.toLong()}")
    }
}
