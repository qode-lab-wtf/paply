package com.paply.thoughts

import com.paply.core.AudioEncoder
import com.paply.thoughts.store.WAVWriter
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Test

class PCM16WriterTest {
    @Test fun everyPCM16ValueSurvivesStorageAndCallerMutation() {
        val path = Files.createTempFile("pcm16", ".wav")
        try {
            val samples = ShortArray(65536) { (it - 32768).toShort() }
            val expected = AudioEncoder.wav(samples)
            val writer = WAVWriter(path)
            writer.append(samples)
            samples.fill(0)
            writer.close()
            assertArrayEquals(expected, Files.readAllBytes(path))
        } finally { Files.deleteIfExists(path) }
    }
}
