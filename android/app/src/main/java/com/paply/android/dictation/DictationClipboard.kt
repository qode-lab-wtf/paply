package com.paply.android.dictation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import com.paply.android.MainActivity
import java.util.UUID

/** Application-owned timer survives keyboard destruction. Never clears somebody else's clip. */
internal object DictationClipboard {
    const val TTL_MS = 120_000L
    private const val OWNER = "com.paply.clip.id"
    private const val EXPIRES = "com.paply.clip.expiresAt"
    private const val CHANNEL = "paply-dictation-result"
    private const val NOTICE = 3102
    private val handler = Handler(Looper.getMainLooper())

    fun copy(context: Context, text: String, notify: Boolean = false, retained: Boolean = true): Boolean = runCatching {
        val app = context.applicationContext
        val manager = app.getSystemService(ClipboardManager::class.java)
        val token = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("Paply", text)
        clip.description.extras = PersistableBundle().apply {
            // Literal is supported on API 29+, including before the SDK constant was added.
            putBoolean("android.content.extra.IS_SENSITIVE", true)
            putString(OWNER, token)
            putLong(EXPIRES, System.currentTimeMillis() + TTL_MS)
        }
        manager.setPrimaryClip(clip)
        handler.postDelayed({ expire(app, token) }, TTL_MS)
        if (notify) runCatching { notification(app, retained) }.onFailure { com.paply.android.Diag.event("ime.notification.failed") }
        true
    }.getOrDefault(false)

    /** Android returns null while locked/background and when another IME is selected.
     * Recheck on the next Paply input view/unlock; never guess ownership or clear a foreign clip.
     * The deadline lives in the clip itself and therefore also survives process death.
     */
    fun clearExpired(context: Context, now: Long = System.currentTimeMillis()) {
        runCatching {
            val extras = context.getSystemService(ClipboardManager::class.java).primaryClipDescription?.extras ?: return
            val token = extras.getString(OWNER) ?: return
            val expires = extras.getLong(EXPIRES, Long.MAX_VALUE)
            if (now >= expires) expire(context, token)
        }
    }

    internal fun expire(context: Context, token: String) {
        runCatching {
            val manager = context.getSystemService(ClipboardManager::class.java)
            if (manager.primaryClipDescription?.extras?.getString(OWNER) == token) {
                manager.clearPrimaryClip()
                context.getSystemService(NotificationManager::class.java).cancel(NOTICE)
            }
        }
    }

    private fun notification(app: Context, retained: Boolean) {
        val manager = app.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Diktat bereit", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null); enableVibration(false)
        })
        val open = PendingIntent.getActivity(app, NOTICE, Intent(app, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(NOTICE, androidx.core.app.NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(com.paply.android.R.drawable.ic_stat_paply)
            .setContentTitle("Text liegt in der Zwischenablage")
            .setContentText(if (retained) "Dein Text bleibt im Paply-Verlauf gesichert" else "Bitte jetzt einsetzen · Verlauf konnte nicht gespeichert werden")
            .setVisibility(androidx.core.app.NotificationCompat.VISIBILITY_SECRET).setSilent(true).setAutoCancel(true)
            .setContentIntent(open).setTimeoutAfter(TTL_MS).build())
    }
}
