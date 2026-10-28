package com.paply.android.dictation

import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Looper
import java.time.Duration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ClipboardTest {
    @Test fun sensitiveClipExpiresAfterTwoMinutesWithSilentPrivateNotification() {
        val app = RuntimeEnvironment.getApplication()
        val clipboard = app.getSystemService(ClipboardManager::class.java)
        assertTrue(DictationClipboard.copy(app, "Mein privater Text", notify = true))
        assertTrue(clipboard.primaryClipDescription!!.extras!!.getBoolean("android.content.extra.IS_SENSITIVE"))
        val manager = app.getSystemService(NotificationManager::class.java)
        val notification = shadowOf(manager).allNotifications.single()
        assertEquals("Text liegt in der Zwischenablage", notification.extras.getString("android.title"))
        assertEquals(android.app.Notification.VISIBILITY_SECRET, notification.visibility)
        val channel = manager.getNotificationChannel(notification.channelId)
        assertNull(channel.sound); assertFalse(channel.shouldVibrate())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(119_999))
        assertTrue(clipboard.hasPrimaryClip())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1))
        assertFalse(clipboard.hasPrimaryClip())
    }
    @Test fun expiryLeavesForeignClipAndNewPaplyClipAlone() {
        val app = RuntimeEnvironment.getApplication()
        val clipboard = app.getSystemService(ClipboardManager::class.java)
        DictationClipboard.copy(app, "alt")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(60))
        DictationClipboard.copy(app, "neu")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(60))
        assertEquals("neu", clipboard.primaryClip!!.getItemAt(0).text.toString())
        clipboard.setPrimaryClip(ClipData.newPlainText("Andere App", "behalten"))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(60))
        assertEquals("behalten", clipboard.primaryClip!!.getItemAt(0).text.toString())
    }
    @Test fun overdueClipIsRecheckedAfterAccessReturnsWithoutClearingForeignText() {
        val app = RuntimeEnvironment.getApplication()
        val clipboard = app.getSystemService(ClipboardManager::class.java)
        DictationClipboard.copy(app, "Paply")
        DictationClipboard.clearExpired(app, System.currentTimeMillis() + 120_001L)
        assertFalse(clipboard.hasPrimaryClip())
        clipboard.setPrimaryClip(ClipData.newPlainText("Andere App", "behalten"))
        DictationClipboard.clearExpired(app, Long.MAX_VALUE)
        assertTrue(clipboard.hasPrimaryClip())
    }

}
