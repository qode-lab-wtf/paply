package com.paply.android.thoughts

import com.paply.android.CaptureResult
import com.paply.android.dictation.RecordingConfigPoll
import java.io.File
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder

class CaptureSafetyTest {
    @get:Rule val temporary = TemporaryFolder()
    @Test fun deleteCallbackRepostsEvenWhileAndroidStillListsOldNotification() {
        val guard = RecordingVisibilityGuard()
        var posts = 0
        assertTrue(guard.dismissed(10) { posts++ })
        assertEquals(1, posts)
        assertTrue(guard.check(11, false, { true }, { true }, { error("duplicate") }))
        assertFalse(guard.dismissed(12) { throw SecurityException() })
    }
    @Test fun dismissedNotificationReappearsAndFailedRepostEndsCapture() {
        val guard = RecordingVisibilityGuard()
        var posted = false
        var reposts = 0
        assertTrue(guard.check(0, false, { true }, { posted }, { reposts++; posted = true }))
        assertEquals(1, reposts)
        assertTrue(guard.check(500, false, { true }, { posted }, { error("duplicate") }))
        posted = false
        assertFalse(guard.check(1000, false, { true }, { posted }, { throw SecurityException() }))
    }
    @Test fun silentlyRejectedRepostHasBoundedGraceAndRevocationRequiresCard() {
        val guard = RecordingVisibilityGuard()
        assertTrue(guard.check(0, false, { true }, { false }, {}))
        assertTrue(guard.check(100, false, { true }, { false }, { error("duplicate") }))
        assertFalse(guard.check(500, false, { true }, { false }, {}))
        assertFalse(guard.check(1000, false, { false }, { true }, {}))
        assertTrue(guard.check(1000, true, { false }, { false }, {}))
    }
    @Test fun initializationFailureIsRetriedAndConcurrentWaitersShareSuccess() = runBlocking {
        var attempts = 0
        val ready = RetryableReady {
            attempts++
            delay(10)
            if (attempts == 1) throw java.io.IOException("disk unavailable")
            Any()
        }
        assertTrue(runCatching { ready.get() }.isFailure)
        val values = (1..20).map { async(Dispatchers.Default) { ready.get() } }.awaitAll()
        assertEquals(2, attempts)
        assertTrue(values.all { it === values.first() })
    }
    @Test fun notificationAvailabilityIsCachedForOneSecond() {
        val cache = VisibilityCache()
        var calls = 0
        for (time in 0L..999L) assertTrue(cache.get(time) { calls++; true })
        assertEquals(1, calls)
        assertFalse(cache.get(1000) { calls++; false })
        assertEquals(2, calls)
    }
    @Test fun recorderPlatformRefreshIsNeverMoreFrequentThan500ms() {
        val poll = RecordingConfigPoll()
        var previous: Long? = null
        for (time in 0L..5000L) if (poll.due(time)) {
            previous?.let { assertTrue(time - it >= 500) }; previous = time
        }
    }
    @Test fun zeroDurationAndSilenceNeverClaimSavedButPartialErrorDoes() {
        val file = temporary.newFile().apply { writeBytes(ByteArray(44)) }
        assertEquals("Nichts gespeichert", captureEndMessage(false, CaptureResult(file, 0, 0, false, "read")))
        file.appendBytes(ByteArray(3200))
        assertEquals("Nichts gespeichert", captureEndMessage(false, CaptureResult(file, 100, 0, false, null)))
        assertTrue(captureEndMessage(false, CaptureResult(file, 100, 0, false, "read")).startsWith("Gedanke gesichert"))
        assertEquals("Verworfen", captureEndMessage(true, CaptureResult(file, 0, 0, false, null)))
    }
}
