package com.paply.android.button

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.animation.ValueAnimator
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.SystemClock
import android.view.*
import android.view.accessibility.*
import android.widget.*
import com.paply.android.*
import com.paply.android.dictation.*
import com.paply.android.history.*
import com.paply.android.settings.SettingsRepository
import kotlinx.coroutines.*

class PaplyButtonService : AccessibilityService() {
    companion object { internal var connected: PaplyButtonService? = null; private set }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var phase = ButtonPolicy.Phase.IDLE
    private var session: DictationSession? = null
    private var preparing: Job? = null
    private var field: AccessibilityNodeInfo? = null
    private var origin: AccessibilityNodeInfo? = null
    private var changed = false
    private var eligible = false
    private var keyboardTop = 0
    private var generation = 0
    private var foreground = false
    internal var awaitingForeground = false; private set
    private var overlayFailed = false
    private var bar: LinearLayout? = null
    private var label: TextView? = null
    private var logo: ImageView? = null
    private var cancel: TextView? = null
    private lateinit var wm: WindowManager
    private lateinit var layout: WindowManager.LayoutParams
    private val position by lazy { getSharedPreferences("paply-button", MODE_PRIVATE) }
    private var offset = 0

    override fun onServiceConnected() {
        connected = this
        wm = getSystemService(WindowManager::class.java)
        offset = position.getInt("offset", 0)
        if (Build.VERSION.SDK_INT >= 33) serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_INPUT_METHOD_EDITOR
        }
        scope.launch { SettingsRepository.get(this@PaplyButtonService).state.collect { inspect() } }
        scope.launch {
            while (isActive) {
                inspect()
                val active = session
                if (phase == ButtonPolicy.Phase.RECORDING && active != null) {
                    if (active.recording.interrupted || (!foreground && !active.recording.hasSignal &&
                        SystemClock.elapsedRealtime() - active.recording.startedAt > 1800)) {
                        if (!foreground && !active.speechDetected) retryForeground(active)
                        else { hint("Mikrofon belegt oder gesperrt. Aufnahme beendet."); finish() }
                    }
                }
                render(); delay(100)
            }
        }
    }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (phase != ButtonPolicy.Phase.IDLE && event?.eventType == AccessibilityEvent.TYPE_VIEW_FOCUSED &&
            event.source?.let { it != origin && it.isEditable } == true) changed = true
        inspect()
    }
    // Deliberately never access event text, node text, hint, description or selection.
    private fun inspect() {
        if (!::wm.isInitialized) return
        val windows = runCatching { windows }.getOrDefault(emptyList())
        val keyboard = windows.filter { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
            .map { Rect().also(it::getBoundsInScreen) }.filter { !it.isEmpty }
        keyboardTop = keyboard.minOfOrNull { it.top } ?: resources.displayMetrics.heightPixels
        val next = windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive }
            ?.root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        eligible = ButtonPolicy.visible(SettingsRepository.get(this).state.value.paplyButton,
            next?.isFocused == true, next?.isEditable == true, next?.isPassword == true, keyboard.isNotEmpty() &&
                getSystemService(android.os.PowerManager::class.java).isInteractive &&
                !getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        field = next
        if (phase != ButtonPolicy.Phase.IDLE && (changed || next != origin || !eligible)) {
            changed = true
            if (phase == ButtonPolicy.Phase.STARTING) discard("Feld gewechselt. Aufnahme abgebrochen.")
            else if (phase == ButtonPolicy.Phase.RECORDING) { hint("Feld gewechselt. Text wird gesichert."); finish() }
        }
        render()
    }
    private fun transition(event: ButtonPolicy.Event) { phase = ButtonPolicy.next(phase, event); render() }
    private fun start() {
        inspect()
        if (overlayFailed || !eligible || phase != ButtonPolicy.Phase.IDLE) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            hint("Öffne Paply und erlaube das Mikrofon."); return
        }
        if (MicrophoneLease.isBusy()) { hint("Das Mikrofon ist gerade belegt."); return }
        origin = field; changed = false
        bar?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        transition(ButtonPolicy.Event.START)
        if (SettingsRepository.get(this).state.value.buttonForeground) requestForeground() else begin()
    }
    private fun begin() {
        if (phase != ButtonPolicy.Phase.STARTING || overlayFailed || connected !== this) return
        val token = generation
        preparing = scope.launch {
            var active: DictationSession? = null
            try {
                active = DictationSession.prepare(this@PaplyButtonService)
                if (token != generation || !eligible || changed) { active.discard(); return@launch }
                session = active
                active.start()
                Diag.event("button.microphone path=${if (foreground) "foreground" else "direct"}")
                transition(ButtonPolicy.Event.READY)
                observe(active)
            } catch (e: CancellationException) { active?.discard(); throw e }
            catch (e: Exception) {
                active?.discard(); session = null
                if (e is MicrophoneBusyException) { discard("Das Mikrofon ist gerade belegt."); return@launch }
                if (!foreground) requestForeground() else discard("Mikrofon nicht verfügbar. Prüfe Rechte und Mikrofon-Sperre.")
            }
        }
    }
    private suspend fun retryForeground(active: DictationSession) {
        val token = generation
        session = null; phase = ButtonPolicy.Phase.STARTING
        active.discard(); active.recording.awaitEnd()
        if (token != generation || phase != ButtonPolicy.Phase.STARTING || changed || !eligible) return
        hint("Mikrofon wird neu verbunden. Bitte gleich sprechen.")
        requestForeground()
    }
    private fun requestForeground() {
        if (awaitingForeground) return
        awaitingForeground = true
        try { startForegroundService(Intent(this, ButtonMicrophoneService::class.java)) }
        catch (_: Exception) { foregroundFailed() }
        val token = generation
        scope.launch { delay(4000); if (token == generation && awaitingForeground) foregroundFailed() }
    }
    internal fun foregroundReady() {
        if (!awaitingForeground || phase != ButtonPolicy.Phase.STARTING) { stopForeground(); return }
        awaitingForeground = false; foreground = true; begin()
    }
    internal fun foregroundFailed() { discard("Mikrofon nicht verfügbar. Öffne Paply und prüfe die Mikrofonfreigabe.") }
    internal fun foregroundStopped() {
        if (foreground && phase == ButtonPolicy.Phase.RECORDING) { hint("Mikrofondienst beendet."); finish() }
        foreground = false
    }
    private fun stopForeground() {
        foreground = false; awaitingForeground = false
        // An old processing result must not stop a newly connected service's recorder.
        if (connected == null || connected === this) stopService(Intent(this, ButtonMicrophoneService::class.java))
    }
    private fun observe(active: DictationSession) {
        // A finished recording survives service disconnection and still reaches history/clipboard.
        DictationRuntime.scope.launch {
            active.state.collect { state ->
                if (session !== active) { cancel(); return@collect }
                when (state.phase) {
                    "working" -> { phase = ButtonPolicy.Phase.WORKING
                        active.recording.awaitEnd(); stopForeground()
                        if (active.limitReached) hint("10 Minuten erreicht. Dein Text wird verarbeitet.") }
                    "result", "failed" -> {
                        state.entry?.let { entry ->
                            if (entry.text.isNotBlank()) deliver(entry)
                            else hint(state.error ?: "Das hat nicht geklappt. Öffne den Verlauf für einen Neuversuch.")
                        }
                        session = null; stopForeground(); transition(ButtonPolicy.Event.RESULT); cancel()
                    }
                    "discarded" -> {
                        val audio = active.recording.awaitEnd()
                        if (audio.error != null && !foreground && !changed && eligible && connected === this@PaplyButtonService) {
                            session = null; phase = ButtonPolicy.Phase.STARTING
                            hint("Mikrofon wird neu verbunden. Bitte gleich sprechen.")
                            requestForeground(); cancel(); return@collect
                        }
                        session = null; stopForeground(); transition(ButtonPolicy.Event.SILENCE)
                        hint(if (audio.error != null) "Mikrofon unterbrochen. Bitte erneut versuchen."
                            else if (active.limitReached) "10 Minuten erreicht. Keine Sprache erkannt." else "Keine Sprache erkannt.")
                        cancel()
                    }
                }
                render()
            }
        }
    }
    private fun sameField(): Boolean {
        inspect()
        return connected === this && eligible && !changed && origin == field && field?.isPassword == false
    }
    private suspend fun deliver(entry: HistoryEntry) {
        val sent = ButtonPolicy.insert(Build.VERSION.SDK_INT, ::sameField, {
            if (Build.VERSION.SDK_INT >= 33) {
                val connection = inputMethod?.currentInputConnection
                if (connection != null) { connection.commitText(entry.text, 1, null); true } else false
            } else false
        }, {
            ButtonClipboard(getSystemService(ClipboardManager::class.java)).paste(entry.text,
                { sameField() && field?.performAction(AccessibilityNodeInfo.ACTION_PASTE) == true },
                { restore -> DictationRuntime.scope.launch { delay(500); runCatching(restore) } })
        })
        val accepted = sent && sameField()
        val retained = entry.failure !in listOf(HistoryFailure.STORAGE, HistoryFailure.STORAGE_FULL)
        val copied = (!accepted || !retained) && DictationClipboard.copy(this, entry.text, notify = true, retained = retained)
        val message = if (!retained) "Verlauf konnte nicht gespeichert werden. Bitte den Text jetzt kopieren oder einsetzen."
            else if (accepted) "An Textfeld gesendet. Im Verlauf gesichert."
            else if (copied) "Feld lange drücken → Einfügen. Text auch im Verlauf."
            else "Text wartet im Verlauf. Dort kopieren und im Feld einsetzen."
        runCatching { HistoryStore.get(this).updateIfPresent(entry.copy(
            status = if (accepted) HistoryStatus.OK else HistoryStatus.PENDING, error = message)) }
        hint(message)
    }
    private fun finish() { transition(ButtonPolicy.Event.FINISH); session?.finish() }
    private fun discard(message: String = "Aufnahme verworfen.") {
        generation++; preparing?.cancel(); preparing = null
        val active = session; session = null; active?.discard()
        stopForeground(); transition(ButtonPolicy.Event.DISCARD); hint(message)
    }
    private fun hint(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show(); render()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        if (!::wm.isInitialized || connected !== this) return
        val show = !overlayFailed && (eligible || phase != ButtonPolicy.Phase.IDLE)
        if (!show) {
            bar?.let { view ->
                bar = null
                if (ValueAnimator.areAnimatorsEnabled()) view.animate().alpha(0f).setDuration(140).withEndAction { runCatching { wm.removeView(view) } }.start()
                else runCatching { wm.removeView(view) }
            }; return
        }
        if (bar == null) {
            val view = LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
                background = GradientDrawable().apply { setColor(Color.rgb(15, 44, 32)); cornerRadius = dp(24).toFloat() }
                elevation = dp(6).toFloat()
            }
            logo = ImageView(this).apply { setImageResource(R.drawable.ic_paply); contentDescription = "Paply-Diktat starten"; setPadding(dp(10),dp(10),dp(10),dp(10)) }
            label = TextView(this).apply { setTextColor(Color.WHITE); textSize = 13f; setPadding(dp(8),0,dp(8),0) }
            cancel = TextView(this).apply { text = "✕"; textSize = 20f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); contentDescription = "Aufnahme verwerfen"; setOnClickListener { discard() } }
            view.addView(logo, LinearLayout.LayoutParams(dp(44),dp(44)))
            view.addView(label, LinearLayout.LayoutParams(-2,dp(44)))
            view.addView(cancel, LinearLayout.LayoutParams(dp(44),dp(44)))
            layout = WindowManager.LayoutParams(-2, dp(44), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.RIGHT; x = dp(8) }
            bar = view
            view.setOnClickListener { if (phase == ButtonPolicy.Phase.IDLE) start() else if (phase == ButtonPolicy.Phase.RECORDING) finish() }
            var down = 0f; var initial = 0; var dragged = false
            view.setOnTouchListener { v, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { down = event.rawY; initial = offset; dragged = false; true }
                    MotionEvent.ACTION_MOVE -> {
                        if (kotlin.math.abs(event.rawY - down) > dp(6)) dragged = true
                        if (dragged) { offset = (initial - (event.rawY - down).toInt()).coerceIn(0, (keyboardTop - dp(100)).coerceAtLeast(0)); render() }; true
                    }
                    MotionEvent.ACTION_UP -> { if (dragged) position.edit().putInt("offset", offset).apply() else v.performClick(); true }
                    else -> true
                }
            }
            try { wm.addView(view, layout) } catch (_: Exception) { bar = null; overlayFailed = true; discard("Paply-Knopf kann nicht angezeigt werden. Bedienungshilfe erneut einschalten."); return }
            if (ValueAnimator.areAnimatorsEnabled()) { view.alpha = 0f; view.animate().alpha(1f).setDuration(140).start() }
        }
        val active = session
        val elapsed = active?.let { (SystemClock.elapsedRealtime() - it.recording.startedAt) / 1000 } ?: 0
        logo?.visibility = if (phase == ButtonPolicy.Phase.IDLE) View.VISIBLE else View.GONE
        label?.visibility = if (phase == ButtonPolicy.Phase.IDLE) View.GONE else View.VISIBLE
        cancel?.visibility = if (phase == ButtonPolicy.Phase.IDLE) View.GONE else View.VISIBLE
        label?.text = when (phase) {
            ButtonPolicy.Phase.STARTING -> "Mikrofon …"
            ButtonPolicy.Phase.WORKING -> "schreibt …"
            ButtonPolicy.Phase.RECORDING -> "${"▮".repeat(1 + ((active?.recording?.level ?: 0f) * 5).toInt())}  ${elapsed / 60}:${(elapsed % 60).toString().padStart(2,'0')} · Fertig" + if (elapsed >= 540) " · noch ${600-elapsed}s" else ""
            else -> ""
        }
        layout.y = (keyboardTop - dp(52) - offset).coerceAtLeast(dp(28))
        bar?.let { runCatching { wm.updateViewLayout(it, layout) } }
    }
    override fun onInterrupt() {
        if (phase == ButtonPolicy.Phase.STARTING) discard("Aufnahme unterbrochen.")
        if (phase == ButtonPolicy.Phase.RECORDING) { changed = true; hint("Aufnahme unterbrochen. Text wird gesichert."); finish() } }
    override fun onDestroy() {
        connected = null; changed = true; generation++; preparing?.cancel()
        if (phase == ButtonPolicy.Phase.RECORDING) { hint("Paply-Knopf beendet. Text wird gesichert."); session?.finish() }
        stopForeground(); scope.cancel()
        bar?.let { runCatching { wm.removeViewImmediate(it) } }; bar = null
        super.onDestroy()
    }
}
