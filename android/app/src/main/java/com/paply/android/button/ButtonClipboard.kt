package com.paply.android.button

import android.content.ClipData
import android.content.ClipboardManager
import android.os.PersistableBundle
import java.util.UUID

/** Keep the previous clip opaque. Never coerce, inspect or log its contents. */
internal class ButtonClipboard(private val manager: ClipboardManager) {
    fun paste(text: String, action: () -> Boolean, later: (() -> Unit) -> Unit): Boolean {
        val previous = manager.primaryClip
        // Android may deny clipboard reads. Do not replace a clip we cannot restore.
        if (previous == null && manager.hasPrimaryClip()) return false
        val token = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("Paply", text).apply {
            description.extras = PersistableBundle().apply {
                putString("paply.button.owner", token); putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        }
        manager.setPrimaryClip(clip)
        val accepted = runCatching(action).getOrDefault(false)
        if (accepted) later {
            if (manager.primaryClipDescription?.extras?.getString("paply.button.owner") == token) {
                if (previous == null) manager.clearPrimaryClip() else manager.setPrimaryClip(previous)
            }
        }
        return accepted
    }
}
