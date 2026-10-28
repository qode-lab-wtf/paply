package com.paply.android

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import kotlinx.coroutines.*

/** A real, visible bottom card grants the microphone service its while-in-use start context. */
class CaptureActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var requested = false
    private lateinit var content: LinearLayout
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        window.setGravity(Gravity.BOTTOM)
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        content = column()
        setContentView(content)
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        scope.launch { ThoughtState.current.collect { render(it) } }
    }
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        requested = false
    }
    override fun onPostResume() {
        super.onPostResume()
        Diag.event("card.resumed locked=${getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked}")
        if (requested) return
        requested = true
        content.post {
            val error = intent.getStringExtra("error")
            if (error != null) { showError(error); return@post }
            if (!ThoughtState.active && intent.action != ThoughtService.SHOW) {
                ThoughtService.start(this)?.let(::showError)
            }
        }
    }
    private fun render(state: ThoughtState.State) {
        content.removeAllViews()
        if (state.phase == "recording") {
            content.addView(RecordingPanel(this).apply {
                startedAt = android.os.SystemClock.elapsedRealtime() - (System.currentTimeMillis() - state.startedAt)
                onFinish = { ThoughtService.command(this@CaptureActivity, ThoughtService.FINISH) }
                onDiscard = { ThoughtService.command(this@CaptureActivity, ThoughtService.DISCARD) }
                onDismiss = { finish() }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(160)))
            content.addView(button("Fertig") { ThoughtService.command(this, ThoughtService.FINISH) })
            content.addView(button("Verwerfen") { ThoughtService.command(this, ThoughtService.DISCARD) })
            content.addView(label("Nach unten wegwischen: Aufnahme läuft weiter.", 13f))
        } else if (state.phase == "processing") content.addView(label("Paply schreibt …"))
        else {
            content.addView(label(state.message.ifBlank { "Aufnahme startet …" }))
            content.addView(button("Schließen") { finish() })
        }
    }
    private fun showError(error: String) {
        content.removeAllViews(); content.addView(label(error))
        content.addView(button("Paply einrichten") { startActivity(android.content.Intent(this, MainActivity::class.java)); finish() })
    }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
}
