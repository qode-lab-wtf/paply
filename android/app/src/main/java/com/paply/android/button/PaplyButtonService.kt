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
    private val keyboardStability = ButtonKeyboardStability()
    private var keyboardStable = false
    private val fieldStability by lazy { ButtonFieldStability(dp(4)) }
    private var generation = 0
    private var foreground = false
    internal var awaitingForeground = false; private set
    private var overlayFailed = false
    private var bar: LinearLayout? = null
    private var label: TextView? = null
    private var logo: PaplyButtonView? = null
    private var cancel: TextView? = null
    private lateinit var wm: WindowManager
    private lateinit var layout: WindowManager.LayoutParams
    private val position by lazy { getSharedPreferences("paply-button", MODE_PRIVATE) }
    private var hintText: String? = null
    private var hintJob: Job? = null
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
    // Inspection never reads field contents; only the explicit insertion attempt does.
    private fun inspect() {
        if (!::wm.isInitialized) return
        val windows = runCatching { windows }.getOrDefault(emptyList())
        val keyboard = windows.filter { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
            .map { Rect().also(it::getBoundsInScreen) }.filter { !it.isEmpty }
        keyboardStable = keyboardStability.observe(keyboard, SystemClock.elapsedRealtime())
        keyboardTop = keyboard.minOfOrNull { it.top } ?: resources.displayMetrics.heightPixels
        val next = windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive }
            ?.root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        eligible = ButtonPolicy.visible(SettingsRepository.get(this).state.value.paplyButton,
            next?.isFocused == true, next?.isEditable == true, next?.isPassword == true, keyboard.isNotEmpty() &&
                getSystemService(android.os.PowerManager::class.java).isInteractive &&
                !getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        if (next != field || !eligible) fieldStability.reset()
        val fieldBounds = if (eligible) next?.let { Rect().also(it::getBoundsInScreen) } else null
        fieldStability.observe(fieldBounds?.takeUnless { it.isEmpty }?.top, SystemClock.elapsedRealtime())
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
        hintJob?.cancel(); hintText = null
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
                        session = null; stopForeground()
                        if (phase != ButtonPolicy.Phase.SUCCESS) transition(ButtonPolicy.Event.RESULT)
                        else scope.launch { delay(650); if (phase == ButtonPolicy.Phase.SUCCESS) transition(ButtonPolicy.Event.RESULT) }
                        cancel()
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
                            else if (active.limitReached) "10 Minuten erreicht. Keine Sprache erkannt." else "Keine Sprache erkannt. Bitte erneut versuchen.")
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
        var clipboardFallback = false
        var setTextResult = ButtonTextInsertion.Result.UNAVAILABLE
        val sent = ButtonPolicy.insert(Build.VERSION.SDK_INT, ::sameField, {
            if (Build.VERSION.SDK_INT >= 33) {
                val connection = inputMethod?.currentInputConnection
                if (connection != null) { connection.commitText(entry.text, 1, null); true } else false
            } else false
        }, { ButtonTextInsertion.insert(field, entry.text).also { setTextResult = it } }, {
            clipboardFallback = Build.VERSION.SDK_INT in 29..32
            ButtonClipboard(getSystemService(ClipboardManager::class.java)).paste(entry.text,
                { sameField() && field?.performAction(AccessibilityNodeInfo.ACTION_PASTE) == true },
                { restore -> DictationRuntime.scope.launch { delay(500); runCatching(restore) } }, retain = clipboardFallback)
        })
        val accepted = sent == ButtonTextInsertion.Result.VERIFIED &&
            (setTextResult == ButtonTextInsertion.Result.VERIFIED || sameField())
        val retained = entry.failure !in listOf(HistoryFailure.STORAGE, HistoryFailure.STORAGE_FULL)
        val copied = setTextResult == ButtonTextInsertion.Result.UNAVAILABLE && (!accepted || !retained) && DictationClipboard.copy(this, entry.text, notify = true, retained = retained)
        val message = if (sent == ButtonTextInsertion.Result.REVIEW) "Textfeld nimmt Text nicht sicher an. Bitte prüfen."
            else if (!retained && !accepted) {
                if (copied) "Text in Zwischenablage. Jetzt einfügen; Verlauf nicht gespeichert."
                else "Text konnte nicht gesichert werden. Bitte erneut versuchen."
            }
            else if (accepted) null
            else if (copied || clipboardFallback) "Text in Zwischenablage. Feld lange drücken → Einfügen."
            else "Text nur im Verlauf. Dort kopieren und einsetzen."
        runCatching { HistoryStore.get(this).updateIfPresent(entry.copy(
            status = if (accepted) HistoryStatus.OK else HistoryStatus.PENDING, error = message)) }
        if (message != null) hint(message)
        if (accepted) transition(ButtonPolicy.Event.SUCCESS)
    }
    private fun finish() { transition(ButtonPolicy.Event.FINISH); session?.finish() }
    private fun discard(message: String? = null) {
        generation++; preparing?.cancel(); preparing = null
        val active = session; session = null; active?.discard()
        stopForeground(); transition(ButtonPolicy.Event.DISCARD)
        if (message != null) hint(message)
        else { hintJob?.cancel(); hintText = null; render() }
    }

    private fun hint(message: String) {
        hintJob?.cancel()
        hintText = when {
            message.startsWith("10 Minuten") -> message
            message.contains("Schlüssel", true) -> "Schlüssel fehlt oder ist ungültig"
            message.contains("Keine Sprache", true) -> "Keine Sprache erkannt. Bitte erneut versuchen."
            message.contains("belegt", true) -> "Mikrofon belegt"
            message.contains("Einfügen") -> "Feld lange drücken → Einfügen"
            message.startsWith("Mikrofon wird") -> "Mikrofon startet neu …"
            message.startsWith("Feld gewechselt") -> "Feld gewechselt · Text wird gesichert"
            message.startsWith("Öffne Paply") || message.startsWith("Mikrofon nicht verfügbar") -> "Mikrofon in Paply freigeben"
            else -> message
        }
        render()
        hintJob = scope.launch {
            delay(4000)
            hintText = null; render()
        }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        if (!::wm.isInitialized || connected !== this) return
        val screen = android.graphics.Point().also { @Suppress("DEPRECATION") wm.defaultDisplay.getRealSize(it) }
        val insets = bar?.rootWindowInsets
        @Suppress("DEPRECATION")
        val safeTop = maxOf(insets?.stableInsetTop ?: dp(28), insets?.displayCutout?.safeInsetTop ?: 0)
        val safeLeft = maxOf(insets?.displayCutout?.safeInsetLeft ?: 0, insets?.stableInsetLeft ?: 0)
        val safeRight = maxOf(insets?.displayCutout?.safeInsetRight ?: 0, insets?.stableInsetRight ?: 0)
        val size = if (phase == ButtonPolicy.Phase.IDLE) dp(56) else dp(72)
        val inset = (dp(72) - size) / 2
        val y = ButtonPosition.fieldTop(keyboardTop.coerceAtMost(screen.y), screen.y,
            fieldStability.top, safeTop, dp(72), dp(8), offset)?.plus(inset)
        val show = keyboardStable && y != null && !overlayFailed && (eligible || phase != ButtonPolicy.Phase.IDLE || hintText != null)
        if (!show) {
            bar?.let { view ->
                logo?.stopAnimation()
                bar = null
                if (keyboardStable && ValueAnimator.areAnimatorsEnabled()) view.animate().alpha(0f).setDuration(140).withEndAction { runCatching { wm.removeView(view) } }.start()
                else runCatching { wm.removeView(view) }
            }; return
        }
        if (bar == null) {
            val view = LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
            logo = PaplyButtonView(this).apply {
                level = { session?.recording?.level ?: 0f }
                setOnClickListener { if (phase == ButtonPolicy.Phase.IDLE) start() else if (phase == ButtonPolicy.Phase.RECORDING) finish() }
            }
            label = TextView(this).apply { setTextColor(Color.WHITE); textSize = 13f; gravity = Gravity.CENTER_VERTICAL; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(dp(8),0,dp(8),0) }
            cancel = TextView(this).apply { text = "✕"; textSize = 20f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); contentDescription = "Aufnahme verwerfen"; setOnClickListener { discard() } }
            label?.background = GradientDrawable().apply { setColor(Color.rgb(15, 44, 32)); cornerRadius = dp(16).toFloat() }
            cancel?.background = GradientDrawable().apply { setColor(Color.rgb(15, 44, 32)); shape = GradientDrawable.OVAL }
            view.addView(label, LinearLayout.LayoutParams(-2,dp(48)))
            view.addView(cancel, LinearLayout.LayoutParams(dp(48),dp(48)))
            view.addView(logo, LinearLayout.LayoutParams(size,size))
            layout = WindowManager.LayoutParams(-2, size, WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.RIGHT
                    layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                    if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0) }
            bar = view
            var down = 0f; var initial = 0; var dragged = false
            logo?.setOnTouchListener { v, event ->
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
        logo?.setPhase(phase)
        logo?.let { if (it.layoutParams.width != size) {
            it.layoutParams = LinearLayout.LayoutParams(size, size)
        } }
        label?.visibility = if (hintText == null) View.GONE else View.VISIBLE
        cancel?.visibility = if (phase == ButtonPolicy.Phase.STARTING || phase == ButtonPolicy.Phase.RECORDING) View.VISIBLE else View.GONE
        if (label?.text?.toString().orEmpty() != hintText.orEmpty()) label?.text = hintText
        val horizontal = ButtonPosition.horizontal(screen.x, safeLeft, safeRight, dp(8))
        val controlsWidth = size + (if (cancel?.visibility == View.VISIBLE) dp(48) else 0)
        label?.maxWidth = (horizontal.width - inset - controlsWidth).coerceAtLeast(0)
        bar?.layoutDirection = View.LAYOUT_DIRECTION_LTR
        bar?.measure(View.MeasureSpec.makeMeasureSpec((horizontal.width - inset).coerceAtLeast(0), View.MeasureSpec.AT_MOST), View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY))
        // Fix the actual window width too: a WRAP_CONTENT relayout can otherwise
        // grow beyond the measured left-anchored position on the next frame.
        val previousHeight = layout.height; val previousWidth = layout.width; val previousX = layout.x; val previousY = layout.y
        layout.width = (bar?.measuredWidth ?: size).coerceAtMost(horizontal.width)
        layout.height = size
        layout.x = horizontal.rightMargin + inset
        layout.y = y ?: safeTop
        if (layout.height != previousHeight || layout.width != previousWidth || layout.x != previousX || layout.y != previousY)
            bar?.let { runCatching { wm.updateViewLayout(it, layout) } }
    }
    override fun onInterrupt() {
        if (phase == ButtonPolicy.Phase.STARTING) discard("Aufnahme unterbrochen.")
        if (phase == ButtonPolicy.Phase.RECORDING) { changed = true; hint("Aufnahme unterbrochen. Text wird gesichert."); finish() } }
    override fun onDestroy() {
        connected = null; changed = true; generation++; preparing?.cancel()
        if (phase == ButtonPolicy.Phase.RECORDING) { hint("Paply-Knopf beendet. Text wird gesichert."); session?.finish() }
        stopForeground(); scope.cancel()
        logo?.stopAnimation()
        bar?.let { runCatching { wm.removeViewImmediate(it) } }; bar = null
        super.onDestroy()
    }
}
