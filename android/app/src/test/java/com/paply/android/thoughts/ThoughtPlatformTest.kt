package com.paply.android.thoughts

import android.app.*
import android.appwidget.AppWidgetManager
import android.content.Intent
import com.paply.android.*
import com.paply.thoughts.*
import com.paply.thoughts.store.ThoughtStore
import java.nio.file.Files
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ThoughtPlatformTest {
    @get:Rule val temporary = TemporaryFolder()
    private val context get() = RuntimeEnvironment.getApplication()
    @Test fun onlyDiscardNeedsUnlockAndDismissalTargetsRecording() {
        val n = ThoughtNotifications.recording(context, com.paply.android.ThoughtState.State("recording", id = "current"))
        assertFalse(n.actions[0].isAuthenticationRequired)
        assertTrue(n.actions[1].isAuthenticationRequired)
        assertNotNull(n.deleteIntent)
        val intent = org.robolectric.Shadows.shadowOf(n.deleteIntent).savedIntent
        assertEquals(ThoughtService.REPOST, intent.action)
        assertEquals("current", intent.getStringExtra("thoughtId"))
    }
    @Test fun widgetRefreshDoesNotInvalidateAnAlreadyDeliveredPendingIntent() {
        val before = ThoughtWidget.captureIntent(context, 321)
        val after = ThoughtWidget.captureIntent(context, 321)
        assertEquals(before, after)
        assertFalse(org.robolectric.Shadows.shadowOf(before).isCanceled)
    }
    @Test fun oneFailedDiscardDoesNotBlockOtherMarkersAndIsRetained() {
        val root = temporary.root
        val store = ThoughtStore(root.toPath())
        // Symlink is rejected by safeDirectory; its target must never be removed.
        val outside = temporary.newFolder("outside")
        Files.createDirectories(store.thoughtsDirectory)
        Files.createSymbolicLink(store.directory("bad"), outside.toPath())
        CaptureDiscardJournal.mark(root, "bad")
        val capture = store.beginCapture(ThoughtTrigger.app, Instant.now())
        capture.audio.close()
        CaptureDiscardJournal.mark(root, capture.thought.id)
        CaptureDiscardJournal.recover(root, store)
        assertNull(store.thought(capture.thought.id))
        assertFalse(root.resolve("discard-${capture.thought.id}").exists())
        assertTrue(root.resolve("discard-bad").exists())
        assertTrue(outside.exists())
    }
    @Test fun recoveryAndAudioReleaseRemoveOnlyTrimCopies() {
        val store = ThoughtStore(temporary.root.toPath())
        val capture = store.beginCapture(ThoughtTrigger.app, Instant.now())
        capture.audio.append(FloatArray(16000) { .1f }); val duration = capture.audio.close()
        store.finishCapture(capture.thought.id, duration)
        val dir = capture.audio.url.parent.toFile()
        val trim = dir.resolve(".tmp-trim-audio.wav").apply { writeText("speech") }
        val legacy = dir.resolve("audio.trim.tmp").apply { writeText("speech") }
        TrimResidue.recover(store)
        assertFalse(trim.exists()); assertFalse(legacy.exists()); assertTrue(capture.audio.url.toFile().exists())
        trim.writeText("speech")
        TrimResidue.releaseAudio(store)
        assertTrue(trim.exists()) // No durable source yet.
        store.saveSourceOnce(capture.thought.id, ThoughtSource("Worte", emptyList(), "test", Instant.now(), listOf("de"), 1.0))
        TrimResidue.releaseAudio(store)
        assertFalse(trim.exists()); assertFalse(capture.audio.url.toFile().exists())
        assertEquals("Worte", store.source(capture.thought.id)?.text)
    }
}
