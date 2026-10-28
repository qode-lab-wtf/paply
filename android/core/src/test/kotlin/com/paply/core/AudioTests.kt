package com.paply.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class AudioTests {
    @Test
    fun levelsAndPeriodicity() {
        val frame = VoiceActivityDetector.analyze(Synth.voice(0.03, -20.0))
        expect(abs(frame.dbfs + 20) < 0.5)
        expect(frame.periodicity > 0.9)
        expect(VoiceActivityDetector.analyze(Synth.noise(0.03, -20.0)).periodicity < 0.4)
        expect(VoiceActivityDetector.analyze(FloatArray(480)).dbfs == -120f)
    }

    @Test
    fun digitalSilenceIsNoSpeech() {
        val v = detector(Synth.silence(3.0))
        expect(!v.speechDetected)
        expect(v.floorDbfs == -120.0)
        expect(SilenceFilter.shouldSkipTranscription(v.meta()))
    }

    @Test
    fun roomNoiseIsNoSpeech() {
        val v = detector(Synth.noise(5.0, -50.0))
        expect(!v.speechDetected)
        expect(SilenceFilter.shouldSkipTranscription(v.meta()))
    }

    @Test
    fun shortSpokenWordIsSpeech() {
        val v =
            detector(
                Synth.withFloor(Synth.silence(1.0) + Synth.voice(0.35, -28.0) + Synth.silence(1.0)),
            )
        expect(v.speechDetected)
        expect(!SilenceFilter.shouldSkipTranscription(v.meta()))
    }

    @Test
    fun quietSpeechInLoudRoomIsSpeech() {
        expect(
            detector(
                    Synth.withFloor(
                        Synth.silence(1.0) + Synth.speech(2.0, -30.0) + Synth.silence(1.0),
                        -48.0,
                    ),
                )
                .speechDetected,
        )
    }

    @Test
    fun clicksAreNoSpeech() {
        val v = detector(Synth.withFloor(Synth.clicks(4.0)))
        expect(!v.speechDetected)
        expect(v.meta().voicedMs == 0.0)
    }

    @Test
    fun singleBreathIsNoSpeech() {
        val v =
            detector(
                Synth.withFloor(
                    Synth.silence(1.5) + Synth.noise(0.6, -32.0, 3) + Synth.silence(1.5),
                ),
            )
        expect(!v.speechDetected)
        expect(SilenceFilter.hasLowSpeechActivity(v.meta()))
    }

    @Test
    fun longContinuousSignals() {
        expect(
            detector(
                    Synth.withFloor(
                        Synth.silence(1.0) + Synth.voice(4.0, -20.0) + Synth.silence(1.0),
                    ),
                )
                .speechDetected,
        )
        expect(
            !detector(
                    Synth.withFloor(
                        Synth.silence(1.0) + Synth.noise(4.0, -30.0) + Synth.silence(1.0),
                    ),
                )
                .speechDetected,
        )
        expect(!VoiceActivityDetector.hasSyllabicBurst(listOf(0 to 200)))
        expect(
            VoiceActivityDetector.hasSyllabicBurst(
                listOf(0 to 200, 210 to 12, 225 to 12, 240 to 12),
            ),
        )
    }

    @Test
    fun repeatedBreathingIsNoSpeech() {
        var a = floatArrayOf()
        for (seed in 1..6) a += Synth.noise(0.7, -30.0, seed.toLong()) + Synth.silence(3.0)
        expect(!detector(Synth.withFloor(a)).speechDetected)
    }

    @Test
    fun sustainedWhisperIsSpeech() {
        var w = floatArrayOf()
        for (seed in 1..5) w += Synth.noise(0.3, -34.0, seed.toLong()) + Synth.silence(0.1)
        expect(
            detector(Synth.withFloor(Synth.silence(1.0) + w + Synth.silence(1.0))).speechDetected,
        )
    }

    @Test
    fun blockSizeDoesNotMatter() {
        val a = Synth.withFloor(Synth.silence(0.5) + Synth.speech(1.5) + Synth.silence(0.5))
        expect(detector(a, 1600).frames == detector(a, 333).frames)
        expect(detector(a, 333).frames == detector(a, a.size).frames)
    }

    @Test
    fun earlySyllablesAreJudgedAgainstLaterFloor() {
        val v = VoiceActivityDetector()
        repeat(15) { v.appendFrame(-25f, 0.9f) }
        repeat(110) { v.appendFrame(-50f, 0f) }
        expect(abs(v.floorDbfs + 50) < 0.01)
        expect(v.meta().speechMs == 450.0)
        expect(v.speechDetected)
    }

    @Test
    fun onlyFramesStrictlyAboveFloorPlus15Count() {
        val v = VoiceActivityDetector()
        repeat(100) { v.appendFrame(-50f, 0f) }
        v.appendFrame(-35f, 0f)
        v.appendFrame(-34f, 0f)
        expect(v.meta().speechMs == 30.0)
    }

    @Test
    fun percentileFloor() {
        val v = VoiceActivityDetector()
        repeat(100) { v.appendFrame((-100 + it).toFloat(), 0f) }
        expect(v.floorDbfs == -86.0)
        expect(v.peakDbfs == -1.0)
        expect(v.meta().speechMs == 64 * 30.0)
    }

    private fun cuts(samples: FloatArray, planner: ChunkPlanner = ChunkPlanner()): List<IntRange> {
        val v = VoiceActivityDetector()
        val result = mutableListOf<IntRange>()
        for (offset in samples.indices step 1600) {
            v.process(samples.copyOfRange(offset, minOf(offset + 1600, samples.size)))
            while (true) {
                val cut = planner.nextCut(v) ?: break
                result += cut
            }
        }
        return result
    }

    private fun seconds(end: Int) = end * VoiceActivityDetector.frameMs / 1000

    @Test
    fun cutsInsideTheFirstLongPauseAfterTenSeconds() {
        val c = cuts(Synth.withFloor(Synth.speech(12.0) + Synth.silence(0.8) + Synth.speech(5.0)))
        expect(c.size == 1)
        expect(c[0].first == 0)
        expect(seconds(c[0].last + 1) > 12 && seconds(c[0].last + 1) < 12.8)
    }

    @Test
    fun noCutBeforeTenSeconds() {
        expect(
            cuts(Synth.withFloor(Synth.speech(8.0) + Synth.silence(1.0) + Synth.speech(6.0)))
                .isEmpty(),
        )
    }

    @Test
    fun gapsBetweenWordsNeverCut() {
        expect(cuts(Synth.withFloor(Synth.speech(30.0, gap = 0.3))).isEmpty())
    }

    @Test
    fun relaxedPauseAfterTwentySeconds() {
        val cut =
            cuts(Synth.withFloor(Synth.speech(21.0) + Synth.silence(0.45) + Synth.speech(3.0)))
                .first()
        expect(seconds(cut.last + 1) > 21 && seconds(cut.last + 1) < 21.45)
    }

    @Test
    fun severalChunksAreContiguous() {
        var a = floatArrayOf()
        repeat(4) { a += Synth.speech(11.0) + Synth.silence(0.9) }
        val c = cuts(Synth.withFloor(a))
        expect(c.size == 4)
        for ((x, y) in c.zip(c.drop(1))) expect(x.last + 1 == y.first)
    }

    @Test
    fun silentStretchIsNotAChunk() {
        expect(cuts(Synth.withFloor(Synth.silence(15.0))).isEmpty())
    }

    @Test
    fun worksOverNoisyFloor() {
        val c =
            cuts(
                    Synth.withFloor(
                        Synth.speech(12.0, -22.0) + Synth.silence(0.8) + Synth.speech(4.0, -22.0),
                        -45.0,
                    ),
                )
                .first()
        expect(seconds(c.last + 1) > 12 && seconds(c.last + 1) < 12.8)
    }

    // JVM has no AVAudioFile FLAC codec: verify the lossless WAV default and injected FLAC
    // boundary.
    // Lossless decoding and compression ratio belong to the Android MediaCodec adapter's acceptance
    // tests.
    @Test
    fun flacBoundaryAndLosslessWavFallback() {
        val samples = AudioEncoder.int16(Synth.withFloor(Synth.speech(3.0)))
        val encoded = AudioEncoder.encode(samples)
        expect(!encoded.isFLAC)
        val b = java.nio.ByteBuffer.wrap(encoded.data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.position(44)
        assertArrayEquals(samples, ShortArray(samples.size) { b.short })
        val mock = "fLaC".toByteArray() + ByteArray(64)
        val flac =
            DefaultAudioEncoding(
                    FlacEncoder {
                        assertArrayEquals(samples, it)
                        mock
                    },
                )
                .encode(samples, true)
        expect(flac.isFLAC)
        expect(flac.fileName == "audio.flac")
        assertArrayEquals(mock, flac.data)
    }

    @Test
    fun wavHeader() {
        val data = AudioEncoder.wav(shortArrayOf(0, 1, -1, 32767, -32768))
        expect(data.size == 54)
        expect(data.copyOfRange(0, 4).decodeToString() == "RIFF")
        expect(data.copyOfRange(8, 16).decodeToString() == "WAVEfmt ")
        val b = java.nio.ByteBuffer.wrap(data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        expect(b.getInt(24) == 16000)
        expect(b.getShort(52) == (-32768).toShort())
    }

    @Test
    fun wavFallbackWhenRequested() {
        val e = AudioEncoder.encode(shortArrayOf(1, 2, 3), false)
        expect(!e.isFLAC && e.mimeType == "audio/wav" && e.data.size == 50)
    }

    @Test
    fun emptyAudioFallsBackToWav() {
        expect(!AudioEncoder.encode(shortArrayOf()).isFLAC)
    }

    @Test
    fun floatConversionClamps() {
        assertArrayEquals(
            shortArrayOf(0, 32767, -32768, 32767, -32768, 0, 16383),
            AudioEncoder.int16(floatArrayOf(0f, 1f, -1f, 2f, -2f, Float.NaN, 0.5f)),
        )
    }
}
