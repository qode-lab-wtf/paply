package com.paply.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File
import com.paply.android.settings.KeyVault

/** Shell-only receiver compiled exclusively into debug. No secret in Intent extras or logs. */
class DebugControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        when(intent.getStringExtra("command")) {
            "load-key" -> {
                val file = File(context.filesDir, "debug-groq-key")
                try { if (file.exists()) KeyVault(context).save(file.readText().trim()) }
                finally { file.delete() }
                Diag.event("debug.key.loaded")
            }
            "silence-on" -> CaptureDebug.silenced = true
            "silence-off" -> CaptureDebug.silenced = false
            "dead-object" -> CaptureDebug.deadObject = true
            "nudge-fast" -> CaptureDebug.nudgeEveryMs = 5_000L
            "nudge-normal" -> CaptureDebug.nudgeEveryMs = 120_000L
            "work" -> com.paply.android.thoughts.ThoughtsRepository.get(context).kick("debug")
            "direct-on" -> Settings(context).directTile = true
            "direct-off" -> Settings(context).directTile = false
            "finish" -> ThoughtService.command(context, ThoughtService.FINISH)
            "discard" -> ThoughtService.command(context, ThoughtService.DISCARD)
        }
    }
}
