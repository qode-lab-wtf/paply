package com.paply.core

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Optional external-device fixture; WAV stays outside the repository, with provenance in FIX-IME. */
class CapturedPauseEvidenceTest {
    @Test fun capturedEmulatorPauseRetainsBothSpeechIslandsAndOmitsTheGap() {
        val file = File("../.local/audio/long-pause-captured.wav")
        assumeTrue("Supply the recorded IME-fix evidence WAV in .local/audio", file.isFile)
        val bytes = file.readBytes()
        val buffer = ByteBuffer.wrap(bytes, 44, bytes.size - 44).order(ByteOrder.LITTLE_ENDIAN)
        val pcm = ShortArray((bytes.size - 44) / 2) { buffer.short }
        val vad = VoiceActivityDetector(analyzeQuietFrames = true)
        for (i in pcm.indices step 16000) vad.process(AudioEncoder.floats(pcm.copyOfRange(i, minOf(i + 16000, pcm.size))))
        val frames = vad.frames.subList(334, 9000).filter { it.dbfs > -100 }
        println("noise frames=${frames.size} db=${frames.minOf { it.dbfs }}..${frames.maxOf { it.dbfs }} pitch=${frames.minOf { it.periodicity }}..${frames.maxOf { it.periodicity }}")
        val ranges = LongSilence.ranges(vad, 0, pcm.size)
        println("ranges=${ranges.map { listOf(it.first / 16000.0, (it.last + 1) / 16000.0) }}")
        assertEquals(2, ranges.size)
        assertTrue(ranges.first().first < 16000)
        assertTrue(ranges.last().last >= pcm.size - 16000)
        assertTrue(ranges.sumOf { it.count() } < 20 * 16000)
        assertTrue(ranges.none { it.first < 270 * 16000 && it.last > 10 * 16000 })
    }
}
