package com.paply.android

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.paply.android.dictation.*
import com.paply.android.history.*
import com.paply.android.settings.KeyVault
import kotlinx.coroutines.*

class PaplyIme : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    private val registry = LifecycleRegistry(this)
    private val saved = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = registry
    override val savedStateRegistry get() = saved.savedStateRegistry
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val handler = Handler(Looper.getMainLooper())
    private var root: ComposeView? = null
    private var panel by mutableStateOf(ImePanelState())
    private var session: DictationSession? = null
    private var preparing: Job? = null
    private var observer: Job? = null
    private var retry: Job? = null
    private var retryEpoch = 0
    private var destroyed = false
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) hidden(force = true)
            else if (intent?.action == Intent.ACTION_USER_PRESENT) DictationClipboard.clearExpired(this@PaplyIme)
        }
    }
    private var visible = false
    private var rebuilding = false
    private var rotationUntil = 0L
    private var generation = 0
    private var field: EditorTarget? = null
    private var origin: EditorTarget? = null
    private var fieldChanged = false
    private var handled: String? = null
    private var lastEntry: HistoryEntry? = null
    private var haptic = false
    private var delivering = false
    private val startVisible = Runnable { beginIfVisible() }

    override fun onCreate() {
        super.onCreate(); saved.performAttach(); saved.performRestore(null)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
        ContextCompat.registerReceiver(this, screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF).apply { addAction(Intent.ACTION_USER_PRESENT) }, ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    override fun onCreateInputView(): View {
        // Compose installs its window recomposer above the ComposeView (the IME dialog's root).
        window?.window?.decorView?.apply {
            setViewTreeLifecycleOwner(this@PaplyIme)
            setViewTreeSavedStateRegistryOwner(this@PaplyIme)
        }
        return ComposeView(this).apply {
        setViewTreeLifecycleOwner(this@PaplyIme)
        setViewTreeSavedStateRegistryOwner(this@PaplyIme)
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
        setContent { ImePanel(panel, onFinish = ::finish, onDiscard = ::discard, onPrimary = ::primary,
            onCopy = ::copyLast, onBack = ::previousKeyboard) }
        root = this
        Diag.event("ime.panel.created phase=${panel.phase}")
        }
    }
    override fun onEvaluateFullscreenMode() = false
    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        val next = EditorTarget.from(attribute)
        val rotating = rebuilding || android.os.SystemClock.elapsedRealtime() < rotationUntil
        if ((session != null || retry?.isActive == true) && ImePolicy.fieldChanged(restarting, next == field, rotating)) {
            fieldChanged = true
            if (session?.state?.value?.phase == "recording") finish()
            Diag.event("ime.field.changed")
        }
        Diag.event("ime.editor.start restarting=$restarting id=${next?.fieldId} type=${next?.inputType} rotation=${android.os.SystemClock.elapsedRealtime() < rotationUntil}")
        field = next
    }
    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        visible = true
        DictationClipboard.clearExpired(this)
        if (isPassword(info) && session?.state?.value?.phase == "recording") finish()
        if (session == null && preparing == null && retry?.isActive != true) {
            panel = if (isPassword(info)) ImePanelState("password", title = "Passwortfeld", subtitle = "Hier nimmt Paply nichts auf.")
            else lastEntry?.takeIf { it.status == HistoryStatus.PENDING && it.text.isNotBlank() }?.let {
                ImePanelState("pending", title = "Text wartet", subtitle = "Im Verlauf gesichert. Hier einsetzen oder mit Wischen verwerfen.", canCopy = true)
            } ?: ImePanelState()
        }
        scheduleStart()
    }
    override fun onWindowShown() { super.onWindowShown(); if (visible) scheduleStart() }
    private fun scheduleStart() { handler.removeCallbacks(startVisible); handler.postDelayed(startVisible, 120) }
    private fun beginIfVisible() {
        if (!visible || !isInputViewShown || root?.isAttachedToWindow != true || panel.phase != "idle" || preparing != null || retry?.isActive == true) return
        lastEntry = null
        if (isPassword(currentInputEditorInfo)) { panel = ImePanelState("password", title = "Passwortfeld", subtitle = "Hier nimmt Paply nichts auf."); return }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            panel = ImePanelState("setup", title = "Paply einrichten", subtitle = "Erlaube Paply den Zugriff auf dein Mikrofon."); return
        }
        val token = generation
        panel = ImePanelState("starting", title = "Paply wird bereit …")
        preparing = scope.launch {
            var prepared: DictationSession? = null
            try {
                val keyPresent = withContext(Dispatchers.IO) { try { !KeyVault(this@PaplyIme).read().isNullOrBlank() } catch (e: Exception) { throw KeyAccessException(e) } }
                if (!keyPresent) { panel = ImePanelState("key", title = "Schlüssel neu eintragen", subtitle = "Trage deinen Groq-Schlüssel in Paply ein."); return@launch }
                prepared = DictationSession.prepare(this@PaplyIme)
                if (token != generation || !visible || !isInputViewShown || isPassword(currentInputEditorInfo)) { prepared.discard(); return@launch }
                session = prepared; origin = field; fieldChanged = false; handled = null; haptic = false; lastEntry = null
                prepared.start()
                panel = ImePanelState("recording", startedAt = prepared.recording.startedAt, level = { prepared.recording.level })
                observe(prepared)
                Diag.event("ime.recording")
            } catch (e: CancellationException) { prepared?.discard(); throw e
            } catch (e: Exception) {
                prepared?.discard(); session = null
                panel = errorPanel(ImePolicy.failure(e))
            } finally { if (token == generation) preparing = null }
        }
    }
    private fun observe(active: DictationSession) {
        observer?.cancel()
        observer = DictationRuntime.scope.launch {
            launch {
                while (session === active && active.state.value.phase == "recording") {
                    if (!haptic && active.speechDetected && active.state.value.phase == "recording") {
                        haptic = true
                        root?.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30)
                            HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.KEYBOARD_TAP)
                        Diag.event("ime.speech.haptic")
                    }
                    if (android.os.SystemClock.elapsedRealtime() - active.recording.startedAt >= ImePolicy.WARNING_MS && panel.subtitle.isBlank()) {
                        panel = panel.copy(subtitle = "Noch 1 Minute · nach 10 Minuten wird dein Text verarbeitet.")
                    }
                    delay(40)
                }
            }
            active.state.collect { state ->
                if (session !== active) return@collect
                when (state.phase) {
                    "working" -> {
                        panel = ImePanelState("working", startedAt = android.os.SystemClock.elapsedRealtime(),
                            subtitle = if (active.limitReached) "10 Minuten erreicht · dein Text wird verarbeitet." else "")
                        if (active.limitReached) Toast.makeText(this@PaplyIme, "10 Minuten erreicht. Paply verarbeitet deinen Text.", Toast.LENGTH_LONG).show()
                    }
                    "failed" -> { lastEntry = state.entry; panel = errorPanel(state.entry?.failure, state.error.orEmpty(), !state.entry?.text.isNullOrBlank()) }
                    "result" -> state.entry?.let { if (handled != it.id) { handled = it.id; deliver(it, active.finishTapNs) } }
                    "discarded" -> { if (active.limitReached) Toast.makeText(this@PaplyIme, "10 Minuten erreicht. Keine Sprache erkannt.", Toast.LENGTH_LONG).show(); session = null; panel = ImePanelState(); if (visible) previousKeyboard() }
                }
                if (state.phase in listOf("failed", "result", "discarded")) cancel()
            }
        }
    }
    private fun errorPanel(kind: HistoryFailure?, detail: String = "", canCopy: Boolean = false) = ImePanelState(
        phase = when (kind) { HistoryFailure.KEY -> "key"; HistoryFailure.STORAGE_FULL -> "storage"; HistoryFailure.AUDIO_MISSING -> "audioMissing"; else -> "error" },
        title = kind?.message ?: "Das hat nicht geklappt",
        subtitle = detail.ifBlank { when (kind) {
            HistoryFailure.KEY -> "Öffne Paply und speichere deinen Groq-Schlüssel erneut."
            HistoryFailure.MICROPHONE_BUSY -> "Beende zuerst die andere Aufnahme und versuche es erneut."
            HistoryFailure.STORAGE_FULL -> "Schaffe Platz auf deinem Gerät."
            else -> "Bitte erneut versuchen."
        } }, canCopy = canCopy)
    private fun finish() { session?.finish() }
    private suspend fun deliver(entry: HistoryEntry, finishNs: Long) {
        if (delivering) return
        delivering = true
        try {
            val target = origin
            val deliveryGeneration = generation
            fun sameTarget() = !destroyed && visible && !fieldChanged && target != null && target == field &&
                deliveryGeneration == generation && !isPassword(currentInputEditorInfo)
            val connection = currentInputConnection
            val output = if (sameTarget() && connection != null) spaced(entry.text,
                runCatching { connection.getTextBeforeCursor(1, 0)?.toString() }.getOrNull()) else entry.text
            val sent = sameTarget() && connection != null && runCatching { connection.commitText(output, 1) }.getOrDefault(false)
            fun elapsed() = if (finishNs > 0) (AndroidPaplyClock.monotonicNanos() - finishNs) / 1_000_000 else 0
            // true only acknowledges IPC delivery. The remote editor can still reject it.
            Diag.event("ime.commit sent=$sent chars=${entry.text.length} tapToCommitMs=${elapsed()}")
            var confirmed: Boolean? = null
            if (sent) {
                delay(80)
                if (sameTarget()) confirmed = runCatching {
                    ImePolicy.readback(output.takeLast(128), connection?.getTextBeforeCursor(minOf(output.length + 64, 256), 0)?.toString())
                }.getOrNull()
                Diag.event("ime.editor confirmed=${confirmed ?: "unknown"} tapToEditorMs=${elapsed()}")
            }
            // A transformed/read-protected editor is unknown, never insert a second time.
            val accepted = sent && sameTarget()
            val retained = entry.failure !in listOf(HistoryFailure.STORAGE, HistoryFailure.STORAGE_FULL)
            val copied = (!accepted || confirmed != true) && DictationClipboard.copy(this, entry.text, notify = !visible || destroyed, retained = retained)
            val updated = if (accepted) entry.copy(status = HistoryStatus.OK,
                error = if (confirmed == true) entry.error?.takeIf { it == "Ohne Polieren gespeichert." }
                    else if (copied) "An Textfeld gesendet; Einsetzen unbekannt. Text liegt auch in der Zwischenablage."
                    else "An das Textfeld gesendet. Einsetzen konnte nicht bestätigt werden.")
            else entry.copy(status = HistoryStatus.PENDING, error = if (copied)
                "Einsetzen nicht bestätigt. Text liegt in Zwischenablage und Verlauf."
                else "Einsetzen nicht bestätigt. Text ist im Verlauf gesichert.")
            lastEntry = updated
            runCatching { HistoryStore.get(this@PaplyIme).updateIfPresent(updated) }
                .onFailure { Diag.event("ime.delivery.save.failed") }
            if (accepted) {
                panel = ImePanelState("inserted", title = if (confirmed == true) "Eingesetzt" else "An Textfeld gesendet",
                    subtitle = if (confirmed == true) "" else if (copied) "Einsetzen nicht bestätigt. Text liegt auch in der Zwischenablage."
                        else "Einsetzen nicht bestätigt. Dein Text bleibt im Verlauf gesichert.", canCopy = true)
                // Keep the success and its Back button visible until the user leaves.
            } else {
                if (deliveryGeneration == generation) panel = ImePanelState("pending",
                    title = if (copied) "In Zwischenablage" else "Text wartet",
                    subtitle = if (retained) "Feld gewechselt oder Einsetzen nicht möglich. Dein Text ist im Verlauf gesichert."
                        else "Bitte jetzt einsetzen. Der Verlauf konnte nicht gespeichert werden.", canCopy = true)
                Toast.makeText(this, if (copied) "Paply: Text liegt in der Zwischenablage." else "Paply: Text im Verlauf gesichert.", Toast.LENGTH_LONG).show()
            }
        } finally { delivering = false }
    }
    private fun primary() {
        when (panel.phase) {
            "setup", "key" -> startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
            "password" -> previousKeyboard()
            "pending" -> lastEntry?.let { entry ->
                if (isPassword(currentInputEditorInfo)) return@let
                origin = field; fieldChanged = false
                scope.launch { deliver(entry, 0) }
            }
            "error", "storage", "audioMissing" -> {
                val entry = lastEntry
                if (entry?.audioFile != null) {
                    panel = ImePanelState("working", startedAt = android.os.SystemClock.elapsedRealtime())
                    val retryGeneration = ++retryEpoch
                    retry = DictationRuntime.retry(this, entry) { result ->
                        if (retryGeneration != retryEpoch) return@retry
                        lastEntry = result
                        if (result.text.isNotBlank()) DictationRuntime.scope.launch { deliver(result, 0) }
                        else panel = errorPanel(result.failure, result.error.orEmpty())
                    }
                } else { session = null; panel = ImePanelState(); beginIfVisible() }
            }
        }
    }
    private fun copy(text: String, notify: Boolean = false) = DictationClipboard.copy(this, text, notify)
    private fun copyLast() { lastEntry?.text?.takeIf { it.isNotBlank() }?.let { if (copy(it)) Toast.makeText(this, "In Zwischenablage", Toast.LENGTH_SHORT).show() } }
    private fun discard() {
        generation++; preparing?.cancel(); preparing = null
        retryEpoch++; retry?.cancel(); retry = null
        val active = session
        session = null; observer?.cancel()
        active?.takeIf { it.state.value.phase == "recording" || it.state.value.phase == "working" }?.discard()
        lastEntry = null; panel = ImePanelState(); previousKeyboard()
    }
    private fun previousKeyboard() {
        val changed = runCatching { switchToPreviousInputMethod() }.getOrDefault(false)
        Diag.event("ime.previous success=$changed")
        if (!changed) getSystemService(InputMethodManager::class.java).showInputMethodPicker()
    }
    private fun hidden(force: Boolean = false) {
        handler.removeCallbacks(startVisible)
        val panelShown = isInputViewShown && root?.isShown == true
        Diag.event("ime.hide rebuilding=$rebuilding panel=$panelShown rotation=${android.os.SystemClock.elapsedRealtime() < rotationUntil}")
        if (!force && (rebuilding || (android.os.SystemClock.elapsedRealtime() < rotationUntil && panelShown))) return
        visible = false; generation++; preparing?.cancel(); preparing = null
        val active = session
        if (active?.state?.value?.phase == "recording") {
            if (active.speechDetected) active.finish() else { active.discard(); session = null }
        }
        val terminal = active?.state?.value
        if (terminal?.phase in listOf("failed", "discarded") ||
            (terminal?.phase == "result" && handled == terminal.entry?.id && !delivering)) {
            session = null; observer?.cancel()
        }
    }
    override fun onFinishInputView(finishingInput: Boolean) { hidden(); super.onFinishInputView(finishingInput) }
    override fun onWindowHidden() { hidden(force = true); super.onWindowHidden() }
    override fun onConfigurationChanged(newConfig: Configuration) {
        rebuilding = true
        rotationUntil = android.os.SystemClock.elapsedRealtime() + 1500
        super.onConfigurationChanged(newConfig)
        rebuilding = false
        // Android rebuilds the input view synchronously. Stop if it could not restore a visible panel.
        if (isInputViewShown && root?.isAttachedToWindow == true) { visible = true; Diag.event("ime.rotation.restored phase=${panel.phase}") }
        else hidden()
    }
    override fun onDestroy() {
        destroyed = true
        rebuilding = false; hidden(force = true)
        unregisterReceiver(screenOff)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        scope.cancel(); super.onDestroy()
    }
    companion object {
        fun isPassword(info: EditorInfo?): Boolean {
            val type = info?.inputType ?: return false
            val cls = type and InputType.TYPE_MASK_CLASS
            val variation = type and InputType.TYPE_MASK_VARIATION
            return (cls == InputType.TYPE_CLASS_TEXT && variation in setOf(InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD, InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)) ||
                (cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
        }
        internal fun spaced(text: String, before: String?): String {
            val last = before?.lastOrNull() ?: return text
            val first = text.firstOrNull() ?: return text
            return if (last.isWhitespace() || first.isWhitespace() || last in "„([{/‚«" || first in ",.!?:;)]}“‘»…") text else " $text"
        }
    }
}

private data class EditorTarget(val packageName: String, val fieldId: Int, val inputType: Int,
    val autofillId: android.view.autofill.AutofillId?, val fieldName: String?, val hint: String?) {
    companion object {
        fun from(info: EditorInfo?): EditorTarget? = info?.let {
            EditorTarget(it.packageName.orEmpty(), it.fieldId, it.inputType,
                if (android.os.Build.VERSION.SDK_INT >= 36) it.autofillId else null,
                it.fieldName, it.hintText?.toString())
        }
    }
}
