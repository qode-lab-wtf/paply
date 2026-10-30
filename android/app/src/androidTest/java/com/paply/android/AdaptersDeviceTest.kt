package com.paply.android

import android.media.*
import android.text.InputType
import android.view.inputmethod.EditorInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.dictation.AndroidFlacEncoder
import com.paply.core.*
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class AdaptersDeviceTest {
    @Test fun allPasswordVariantsBlockRecording() {
        for (type in listOf(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD)) {
            assertTrue(PaplyIme.isPassword(EditorInfo().apply { inputType = type or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS }))
        }
        assertFalse(PaplyIme.isPassword(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT }))
        assertFalse(PaplyIme.isPassword(EditorInfo().apply { inputType = InputType.TYPE_CLASS_NUMBER }))
    }
    @Test fun flacRoundTripIsLossless() {
        val samples = ShortArray(27200) { (kotlin.math.sin(it * 2 * Math.PI * 223 / 16000) * 8000).toInt().toShort() }
        val data = requireNotNull(AndroidFlacEncoder().encode(samples))
        assertEquals("fLaC", String(data, 0, 4)); assertEquals(34, data[7].toInt())
        assertTrue(data.size < samples.size * 2)
        val file = File.createTempFile("codec-test", ".flac", InstrumentationRegistry.getInstrumentation().targetContext.cacheDir)
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            file.writeBytes(data); extractor.setDataSource(file.path); extractor.selectTrack(0)
            val format = extractor.getTrackFormat(0)
            assertEquals(16000, format.getInteger(MediaFormat.KEY_SAMPLE_RATE))
            assertEquals(1, format.getInteger(MediaFormat.KEY_CHANNEL_COUNT))
            // Android's FLAC extractor may itself decode to PCM (audio/raw).
            if (format.getString(MediaFormat.KEY_MIME) == MediaFormat.MIMETYPE_AUDIO_RAW) {
                val decoded = ByteArrayOutputStream()
                val buffer = ByteBuffer.allocate(65536)
                while (true) {
                    buffer.clear()
                    val n = extractor.readSampleData(buffer, 0)
                    if (n < 0) break
                    val bytes = ByteArray(n); buffer.position(0); buffer.get(bytes); decoded.write(bytes)
                    extractor.advance()
                }
                val pcm = ByteBuffer.wrap(decoded.toByteArray()).order(ByteOrder.LITTLE_ENDIAN)
                assertArrayEquals(samples, ShortArray(pcm.remaining() / 2) { pcm.short })
                Diag.event("test.flac.lossless samples=${samples.size} bytes=${data.size} wavBytes=${samples.size * 2 + 44}")
                return
            }
            // The platform extractor does not always expose FLAC csd-0. Supply the
            // documented complete metadata config if absent before feeding frame packets.
            if (!format.containsKey("csd-0")) {
                var end = 4
                do {
                    val last = data[end].toInt() and 128 != 0
                    val length = ((data[end + 1].toInt() and 255) shl 16) or
                        ((data[end + 2].toInt() and 255) shl 8) or (data[end + 3].toInt() and 255)
                    end += 4 + length
                } while (!last)
                format.setByteBuffer("csd-0", ByteBuffer.wrap(data.copyOfRange(0, end)))
            }
            codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_FLAC)
            codec.configure(format, null, null, 0); codec.start()
            val decoded = ByteArrayOutputStream(); val info = MediaCodec.BufferInfo()
            var ended = false; var done = false; val deadline = android.os.SystemClock.elapsedRealtime() + 10000
            while (!done && android.os.SystemClock.elapsedRealtime() < deadline) {
                if (!ended) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = requireNotNull(codec.getInputBuffer(index)); buffer.clear()
                        val count = extractor.readSampleData(buffer, 0)
                        ended = count < 0
                        codec.queueInputBuffer(index, 0, if (ended) 0 else count, if (ended) 0 else extractor.sampleTime,
                            if (ended) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                        if (!ended) extractor.advance()
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000)
                if (index >= 0) {
                    val b = requireNotNull(codec.getOutputBuffer(index)).duplicate()
                    b.position(info.offset); b.limit(info.offset + info.size)
                    val bytes = ByteArray(info.size); b.get(bytes); decoded.write(bytes)
                    done = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                }
            }
            assertTrue("FLAC decoder reached EOS", done)
            val b = ByteBuffer.wrap(decoded.toByteArray()).order(ByteOrder.LITTLE_ENDIAN)
            assertArrayEquals(samples, ShortArray(b.remaining() / 2) { b.short })
            Diag.event("test.flac.lossless samples=${samples.size} bytes=${data.size} wavBytes=${samples.size * 2 + 44}")
        } finally { codec?.let { runCatching { it.stop() }; it.release() }; extractor.release(); file.delete() }
    }
    @Test fun encoderFailureFallsBackToWav() {
        val encoded = DefaultAudioEncoding(FlacEncoder { throw IllegalStateException() }).encode(shortArrayOf(1, -3, 8), true)
        assertFalse(encoded.isFLAC); assertEquals("RIFF", String(encoded.data, 0, 4))
    }
}
