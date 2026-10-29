package com.paply.thoughts

import com.paply.thoughts.store.WAVWriter
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class WAVHeaderCompatibilityTest {
    @Test fun truncatedAndInvalidHeadersStillReturnNull() {
        val file = Files.createTempFile("paply-header", ".wav")
        try {
            val header = WAVWriter.header(32000)
            for (length in 0 until WAVWriter.headerSize) {
                Files.write(file, header.copyOf(length))
                assertNull("length $length", WAVWriter.headerDurationMs(file))
            }
            Files.write(file, header)
            assertEquals(1000, WAVWriter.headerDurationMs(file))
            Files.write(file, ByteArray(WAVWriter.headerSize))
            assertNull(WAVWriter.headerDurationMs(file))
        } finally { Files.deleteIfExists(file) }
        assertNull(WAVWriter.headerDurationMs(file))
    }
}
