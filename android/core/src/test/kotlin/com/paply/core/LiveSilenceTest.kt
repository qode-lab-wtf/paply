package com.paply.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class LiveSilenceTest {
    private fun exercise(source: ShortArray): List<ShortArray> = runBlocking {
        val sent = java.util.concurrent.CopyOnWriteArrayList<ShortArray>()
        val encoder = object : AudioEncoding {
            override fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded {
                sent += samples.copyOf()
                return DefaultAudioEncoding().encode(samples, false)
            }
        }
        MockServer { _, _ -> Groq.transcription("Ein vollständiger Satz.") }.use { server ->
            DictationPipeline(PaplySettings(language = "de"), server.client(),
                options = PipelineOptions(polish = false), encoder = encoder).use { pipeline ->
                for (start in source.indices step 320) pipeline.append(source.copyOfRange(start, minOf(start + 320, source.size)))
                assertNull(pipeline.finish().error)
            }
        }
        sent.toList()
    }
    @Test fun longLeadingAndTrailingSilenceIsRemoved() {
        val voice = AudioEncoder.int16(Synth.speech(4.0))
        for (amplitude in listOf(0, 1, 2, 10, 18)) {
            val random = java.util.Random(17)
            // Stationary low-frequency emulator-like noise, about -70 to -90 dBFS.
            var frame: ShortArray
            do {
                var value: Short = 0
                frame = ShortArray(480) { i ->
                    if (i % 8 == 0) value = (random.nextInt(2 * amplitude + 1) - amplitude).toShort()
                    value
                }
                val features = VoiceActivityDetector.analyze(AudioEncoder.floats(frame), -100.0)
            } while (features.periodicity >= .3f || features.zeroCrossings >= .08f)
            val noise = ShortArray(25 * 16000) { frame[it % frame.size] }
            val uploads = exercise(noise + voice + ShortArray(3 * 16000))
            assertTrue(uploads.isNotEmpty())
            assertTrue("Long safe silence must not reach the encoder: amplitude=$amplitude sizes=${uploads.map { it.size }}", uploads.sumOf { it.size } < 7 * 16000)
        }
    }
    @Test fun pauseKeepsEverySpeechSampleIncludingQuietVoice() {
        for (db in listOf(-30.0, -72.0, -82.0)) {
            val first = AudioEncoder.int16(Synth.speech(4.0))
            val last = AudioEncoder.int16(Synth.voice(2.0, db))
            val uploads = exercise(first + ShortArray(3 * 16000) + last)
            val joined = uploads.flatMap { it.toList() }.toShortArray()
            assertArrayEquals(first, joined.copyOfRange(0, first.size))
            assertArrayEquals(last, joined.copyOfRange(joined.size - last.size, joined.size))
            assertTrue(joined.size < first.size + last.size + 16000)
        }
    }
    @Test fun capturedPeriodicEmulatorNoiseIsNotMistakenForSafeSilence() {
        val path = System.getProperty("paply.regression.fixtures") ?: return
        val file = java.io.File(path, "baseline.wav")
        if (!file.exists()) return
        val source = javax.sound.sampled.AudioSystem.getAudioInputStream(file).use { stream ->
            java.nio.ByteBuffer.wrap(stream.readBytes()).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().let { buffer ->
                ShortArray(buffer.remaining()).also { buffer.get(it) }
            }
        }
        val vad = VoiceActivityDetector(analyzeQuietFrames = true)
        vad.process(AudioEncoder.floats(source))
        assertTrue(vad.frames.take(100).any { it.dbfs > -85 && it.periodicity > .6f })
        val uploads = exercise(source)
        println("Captured source=${source.size}; uploaded=${uploads.map { it.size }}")
        assertArrayEquals(source, uploads.flatMap { it.toList() }.toShortArray())
    }
    @Test fun silenceDoesNotUpload() { assertTrue(exercise(ShortArray(28 * 16000)).isEmpty()) }
}
