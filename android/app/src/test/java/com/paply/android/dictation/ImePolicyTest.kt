package com.paply.android.dictation

import com.paply.android.MicrophoneBusyException
import com.paply.android.history.HistoryFailure
import org.junit.Assert.*
import org.junit.Test

class ImePolicyTest {
    @Test fun reusedNonzeroFieldIdStillCountsAsChangeUnlessRotating() {
        assertTrue(ImePolicy.fieldChanged(false, true, false))
        assertTrue(ImePolicy.fieldChanged(true, false, false))
        assertFalse(ImePolicy.fieldChanged(true, true, false))
        assertFalse(ImePolicy.fieldChanged(false, true, true))
    }
    @Test fun normalizedReadbackConfirmsButMismatchAndUnreadableAreUnknown() {
        assertEquals(true, ImePolicy.readback("Hallo,\n WELT!", "Vorher Hallo,\u00a0welt!"))
        assertNull(ImePolicy.readback("Hallo Welt", "Hallo"))
        assertNull(ImePolicy.readback("Hallo", null))
    }
    @Test fun permissionKeyStorageAndBusyAreDistinct() {
        assertEquals(HistoryFailure.KEY, ImePolicy.failure(KeyAccessException()))
        assertEquals(HistoryFailure.STORAGE, ImePolicy.failure(java.io.IOException()))
        assertEquals(HistoryFailure.STORAGE_FULL, ImePolicy.failure(java.io.IOException("No space left on device")))
        assertEquals(HistoryFailure.MICROPHONE_BUSY, ImePolicy.failure(MicrophoneBusyException()))
        assertEquals(HistoryFailure.MICROPHONE, ImePolicy.failure(SecurityException()))
    }
    @Test fun recordingConfigurationIsReadAtMostOncePerSecond() {
        val poll = RecordingConfigPoll()
        assertTrue(poll.due(100))
        for (time in 101L..1099L) assertFalse(poll.due(time))
        assertTrue(poll.due(1100))
        assertFalse(poll.due(1101))
    }
    @Test fun warningIsOneMinuteBeforeTheTenMinuteLimit() {
        assertEquals(600_000L, ImePolicy.MAX_MS)
        assertEquals(60_000L, ImePolicy.MAX_MS - ImePolicy.WARNING_MS)
    }
}
