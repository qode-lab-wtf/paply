package com.paply.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File

/** Shell-only receiver compiled exclusively into debug. No secret in Intent extras or logs. */
class DebugControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        when(intent.getStringExtra("command")) {
            "load-key" -> {
                val file = File(context.filesDir, "debug-groq-key")
                try { if (file.exists()) Settings(context).apiKey = file.readText().trim() }
                finally { file.delete() }
                Diag.event("debug.key.loaded")
            }
            "direct-on" -> Settings(context).directTile = true
            "direct-off" -> Settings(context).directTile = false
            "finish" -> ThoughtService.command(context, ThoughtService.FINISH)
            "discard" -> ThoughtService.command(context, ThoughtService.DISCARD)
        }
    }
}
