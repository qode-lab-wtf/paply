package com.paply.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import com.paply.core.DictationPipeline
import java.io.File
import kotlinx.coroutines.*

class PaplyIme : InputMethodService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var root: LinearLayout
    private var recorder: AudioCapture? = null
    private var job: Job? = null
    private var generation = 0
    private var visible = false
    private var state = "idle"
    private val startVisible = Runnable { beginIfVisible() }
    private fun scheduleStart() {
        root.removeCallbacks(startVisible)
        // Android can finish/restart the input view within the same keyboard transition.
        root.postDelayed(startVisible, 120)
    }
    override fun onCreateInputView(): View {
        root = column().apply { setPadding(dp(6), dp(6), dp(6), dp(6)) }
        return root
    }
    override fun onEvaluateFullscreenMode() = false
    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        if (!restarting) cancelSession("new-input")
    }
    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        visible = true
        scheduleStart()
    }
    override fun onWindowShown() {
        super.onWindowShown()
        if (::root.isInitialized) scheduleStart()
    }
    private fun beginIfVisible() {
        if (!visible || !isInputViewShown || state != "idle") return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            state = "setup"
            message("Paply braucht dein Mikrofon.", "Paply einrichten") { openSetup() }; return
        }
        if (Settings(this).apiKey.isBlank()) {
            state = "setup"
            message("Groq-Schlüssel in Paply eintragen.", "Paply einrichten") { openSetup() }; return
        }
        val recording = AudioCapture(this, File.createTempFile("dictation-", ".wav", cacheDir))
        try {
            recording.start(); recorder = recording; state = "recording"
            root.removeAllViews()
            root.addView(RecordingPanel(this).apply {
                startedAt = recording.startedAt; level = { recording.level }
                onFinish = { finishRecording() }; onDiscard = { discard() }
            })
            Diag.event("ime.recording generation=$generation")
            scope.launch {
                val result = recording.awaitEnd()
                if (recorder === recording && state == "recording") {
                    if (result.error != null) { cancelSession("read-error"); showError("Mikrofon unterbrochen.") }
                    else finishRecording()
                }
            }
        } catch (e: Exception) { recording.file.delete(); showError(safeError(e)) }
    }
    private fun finishRecording() {
        if (state != "recording") return
        val recording = recorder ?: return
        val token = generation
        val connection = currentInputConnection
        state = "processing"
        message("Paply schreibt …")
        job = scope.launch {
            try {
                val audio = recording.finish()
                recorder = null
                if (!audio.usable) { showError(if (audio.silenced) "Mikrofon war stummgeschaltet." else "Keine Sprache aufgenommen."); return@launch }
                val result = DictationPipeline(Settings(this@PaplyIme).client()).dictate(audio.file, audio.durationMs / 1000.0)
                if (token != generation || !visible || connection == null || connection !== currentInputConnection) return@launch
                if (result.text.isBlank()) { showError("Nichts verstanden."); return@launch }
                val inserted = connection.commitText(result.text, 1)
                Diag.event("ime.commit ok=$inserted chars=${result.text.length} model=${result.model} rawFallback=${result.fallbackReason ?: "none"}")
                if (inserted) { state = "done"; previousKeyboard() }
                else showError("Text konnte nicht eingesetzt werden.")
            } catch (e: CancellationException) { throw e
            } catch (e: Exception) { showError(safeError(e))
            } finally { withContext(NonCancellable + Dispatchers.IO) { recording.finish(); recording.file.delete() } }
        }
    }
    private fun discard() { cancelSession("swipe"); previousKeyboard() }
    private fun previousKeyboard() {
        val changed = switchToPreviousInputMethod()
        Diag.event("ime.previous success=$changed")
        if (!changed) getSystemService(InputMethodManager::class.java).showInputMethodPicker()
    }
    private fun showError(text: String) {
        state = "error"
        message(text, "Erneut aufnehmen") { state = "idle"; beginIfVisible() }
    }
    private fun openSetup() {
        // Bring the setup page forward even if a previous capture card is still on its task.
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
    }
    private fun message(text: String, action: String? = null, perform: () -> Unit = {}) {
        root.removeAllViews(); root.minimumHeight = dp(260)
        root.addView(label(text, 20f))
        if (action != null) root.addView(button(action, perform))
        root.addView(button("Tastatur wechseln") { previousKeyboard() })
    }
    private fun cancelSession(reason: String) {
        if (::root.isInitialized) root.removeCallbacks(startVisible)
        generation++; job?.cancel(); job = null
        recorder?.let { recording ->
            recording.requestStop()
            cleanup.launch { recording.awaitEnd(); recording.file.delete() }
        }
        recorder = null; state = "idle"
        Diag.event("ime.end reason=$reason")
    }
    override fun onFinishInputView(finishingInput: Boolean) {
        visible = false; cancelSession("finish-view"); super.onFinishInputView(finishingInput)
    }
    override fun onWindowHidden() { visible = false; cancelSession("window-hidden"); super.onWindowHidden() }
    override fun onDestroy() { visible = false; cancelSession("destroy"); scope.cancel(); super.onDestroy() }
    companion object { private val cleanup = CoroutineScope(SupervisorJob() + Dispatchers.IO) }
}
