package com.paply.core

import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class ImeFixAudioTests {
    @Test fun tenMinutesOfSilenceHaveBoundedIncrementalWorkThenDetectQuietSpeech() {
        val vad = VoiceActivityDetector()
        repeat(20_000) { vad.appendFrame(-100f, 0f) }
        assertFalse(vad.speechDetected)
        assertTrue("Work must be linear with a bounded lookahead tail", vad.detectionVisits < 20_000L * 550)
        repeat(10) { vad.appendFrame(-62f, .9f, .04f) }
        assertTrue(vad.speechDetected)
    }

    @Test fun incrementalDetectionMatchesFullHistoryWithChangingFloorsAndSeparatedRuns() {
        repeat(6) { seed ->
            val random = Random(seed)
            val vad = VoiceActivityDetector()
            var referenceLatched = false
            repeat(2500) { i ->
                val floor = if (i < 1100) -90f else -72f
                val speech = i in 1800..1802 || i in 1900..1902
                vad.appendFrame(if (speech) -50f else floor + random.nextFloat() * 2,
                    if (speech) .9f else 0f, .03f)
                referenceLatched = referenceLatched || vad.hasSpeech(0 until vad.frameCount)
                assertEquals("seed=$seed frame=$i", referenceLatched, vad.speechDetected)
            }
        }
    }

    @Test fun twoMinutePauseIsExcludedAndBothQuietSpeechIslandsAreBitExact() {
        val first = Synth.speech(2.0, -62.0)
        val last = Synth.speech(2.0, -68.0)
        val audio = first + Synth.silence(120.0) + last
        val vad = detector(audio)
        val ranges = LongSilence.ranges(vad, 0, audio.size)
        assertEquals(2, ranges.size)
        assertTrue(ranges.sumOf { it.count() } < 5 * 16000)
        assertEquals(0, ranges.first().first)
        assertEquals(audio.lastIndex, ranges.last().last)
        assertTrue(ranges.first().last >= first.lastIndex)
        assertTrue(ranges.last().first <= first.size + 120 * 16000)
        assertArrayEquals(first, audio.copyOfRange(0, first.size), 0f)
        assertArrayEquals(last, audio.copyOfRange(audio.size - last.size, audio.size), 0f)
    }

    @Test fun shortPausesQuietVoicingAndWhisperLikeFramesAreNeverRemoved() {
        for (pause in listOf(0.3, 1.9)) {
            val audio = Synth.speech(2.0) + Synth.silence(pause) + Synth.speech(2.0)
            assertEquals(listOf(0 until audio.size), LongSilence.ranges(detector(audio), 0, audio.size))
        }
        for (frame in listOf(VoiceActivityDetector.Frame(-72f, .8f, .03f), VoiceActivityDetector.Frame(-63f, .1f, .3f), VoiceActivityDetector.Frame(-80f, 0f, 0f))) {
            val vad = VoiceActivityDetector()
            repeat(4000) { vad.appendFrame(frame.dbfs, frame.periodicity, frame.zeroCrossings) }
            assertEquals(listOf(0 until 4000 * 480), LongSilence.ranges(vad, 0, 4000 * 480))
        }
    }

    @Test fun leadingTrailingAndEntireSilenceProduceNoSilentUploads() {
        val audio = Synth.silence(120.0) + Synth.speech(2.0) + Synth.silence(120.0)
        val range = LongSilence.ranges(detector(audio), 0, audio.size).single()
        assertTrue(range.count() < 3 * 16000)
        val silent = Synth.silence(120.0)
        assertTrue(LongSilence.ranges(detector(silent), 0, silent.size).isEmpty())
    }
    @Test fun fileModeRemovesQuietRoomNoiseButPreservesEvenVeryQuietVoicing() {
        val first = Synth.speech(2.0)
        val last = Synth.speech(3.0, -82.0)
        val audio = AudioEncoder.floats(AudioEncoder.int16(first + Synth.noise(120.0, -85.0) + last))
        val vad = VoiceActivityDetector(analyzeQuietFrames = true)
        for (i in audio.indices step 16000) vad.process(audio.copyOfRange(i, minOf(i + 16000, audio.size)))
        val ranges = LongSilence.ranges(vad, 0, audio.size)
        assertEquals(2, ranges.size)
        assertTrue(ranges.sumOf { it.count() } < 7 * 16000)
        assertTrue(ranges.last().first <= audio.size - last.size)
        assertEquals(audio.lastIndex, ranges.last().last)
    }

    @Test fun periodicPcmDitherDoesNotKeepTwoMinutesOfSilenceAlive() {
        val dither = FloatArray(120 * 16000) { i ->
            if (i % 16000 < 1200) (if (i % 160 < 80) -2 else 1) / 32768f else 0f
        }
        val audio = Synth.speech(2.0) + dither + Synth.speech(2.0, -62.0)
        val vad = VoiceActivityDetector(analyzeQuietFrames = true)
        for (i in audio.indices step 16000) vad.process(audio.copyOfRange(i, minOf(i + 16000, audio.size)))
        val ranges = LongSilence.ranges(vad, 0, audio.size)
        assertEquals(2, ranges.size)
        assertTrue(ranges.sumOf { it.count() } < 5 * 16000)
    }

}
