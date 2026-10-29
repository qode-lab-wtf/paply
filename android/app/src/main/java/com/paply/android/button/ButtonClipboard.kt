package com.paply.android.button

import android.content.ClipData
import android.content.ClipboardManager
import android.os.PersistableBundle
import java.util.UUID

/** Keep readable previous clips opaque. API 29–32's announced fallback retains the
 * dictation: an unfocused service cannot reliably read even hasPrimaryClip there. */
internal class ButtonClipboard(private val manager: ClipboardManager) {
    fun paste(text: String, action: () -> Boolean, later: (() -> Unit) -> Unit, retain: Boolean = false): Boolean {
        val previous = if (retain) null else manager.primaryClip
        // Best effort only; Android can deny both queries. The announced fallback skips them.
        if (!retain && previous == null && manager.hasPrimaryClip()) return false
        val token = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("Paply", text).apply {
            description.extras = PersistableBundle().apply {
                putString("paply.button.owner", token); putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        }
        manager.setPrimaryClip(clip)
        val accepted = runCatching(action).getOrDefault(false)
        if (accepted && !retain) later {
            if (manager.primaryClipDescription?.extras?.getString("paply.button.owner") == token) {
                if (previous == null) manager.clearPrimaryClip() else manager.setPrimaryClip(previous)
            }
        }
        return accepted
    }
}
