package com.paply.android

import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.dictation.DictationSession
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test

class CaptureLimitDeviceTest {
    @Test fun actualRecorderStopsAtTenMinutesWithoutWaitingForAnotherTap() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val session = DictationSession.prepare(app)
        try {
            withContext(Dispatchers.Main) {
                session.start()
                // Move only the recording's monotonic origin; exercise the real AudioRecord loop,
                // limit watcher, silent discard and microphone lease without a 10-minute test sleep.
                AudioCapture::class.java.getDeclaredField("startedAt").apply { isAccessible = true }
                    .setLong(session.recording, SystemClock.elapsedRealtime() - 600_001L)
            }
            withTimeout(5000) { session.state.first { it.phase == "discarded" } }
            assertTrue(session.limitReached)
            assertFalse(session.speechDetected)
            assertFalse(MicrophoneLease.isBusy())
            withTimeout(5000) { while (session.file.exists()) delay(20) }
        } finally { withContext(Dispatchers.Main) { session.discard() } }
    }
}
