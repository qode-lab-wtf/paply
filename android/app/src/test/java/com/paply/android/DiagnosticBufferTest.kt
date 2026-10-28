package com.paply.android

import org.junit.Assert.*
import org.junit.Test

class DiagnosticBufferTest {
    @Test fun onlyApprovedEventNamesAndNumericOrBooleanFieldsEnterMemory() {
        val buffer = DiagnosticBuffer()
        assertNull(buffer.add("user.supplied.text ms=5"))
        buffer.add("dictation.saved chars=42 totalMs=1.5 audio=true raw=secret key=secret language=de result=valid id=123")
        assertEquals(listOf("dictation.saved chars=42 totalMs=1.5 audio=true"), buffer.snapshot())
    }
    @Test fun malformedNumbersAndPartialTokensAreNotExported() {
        val buffer = DiagnosticBuffer()
        buffer.add("audio.stop ms=42secret chars=NaN bytes=Infinity voiced=1e999 silenced=false")
        assertEquals(listOf("audio.stop silenced=false"), buffer.snapshot())
    }
    @Test fun bufferKeepsTheLatestTwoHundredEventsInOrder() {
        val buffer = DiagnosticBuffer()
        repeat(205) { buffer.add("audio.stop ms=$it") }
        val snapshot = buffer.snapshot()
        assertEquals(200, snapshot.size)
        assertEquals("audio.stop ms=5", snapshot.first())
        assertEquals("audio.stop ms=204", snapshot.last())
    }
}
