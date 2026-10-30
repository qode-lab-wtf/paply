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
    private var fieldGapUntil = 0L
    private var keyboardTop = 0
    private var imeBounds = emptyList<ButtonPosition.Box>()
    private var reservedPosition: ButtonPosition.Box? = null
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
    private var maxOffset = 0
    private var fieldBounds: Rect? = null
    private var warning = ButtonRecordingWarning()
    private var amber = false
    private data class RenderKey(val model: ButtonPresentation.Render, val x: Int, val y: Int,
                                 val width: Int, val amber: Boolean, val eligible: Boolean,
                                 val keyboardStable: Boolean, val holding: Boolean,
                                 val ime: List<ButtonPosition.Box>, val safeTop: Int)
    private var lastRender: RenderKey? = null
    private var positionAnimator: ValueAnimator? = null
    private var obstacles = emptyList<ButtonPosition.Box>()
    private var obstaclesDirty = true
    private var obstaclesReadAt = 0L
    private var rotationUntil = 0L
    private var missingSince: Long? = null
    private var originId: String? = null
    private var originPackage: String? = null

    private fun Rect.box() = ButtonPosition.Box(left, top, right, bottom)
    @Suppress("DEPRECATION")
    private fun release(node: AccessibilityNodeInfo?) { if (Build.VERSION.SDK_INT < 33) node?.recycle() }
    private fun collectObstacles(root: AccessibilityNodeInfo): List<ButtonPosition.Box> {
        val result = mutableListOf<ButtonPosition.Box>()
        var visited = 0
        fun visit(node: AccessibilityNodeInfo, depth: Int) {
            if (++visited > 160) return
            if (node.isVisibleToUser && (node.isClickable || node.isEditable)) {
                val rect = Rect().also(node::getBoundsInScreen)
                if (!rect.isEmpty && ButtonPosition.obstacle(rect.width(), rect.height(),
                    node.isEditable, node.isClickable, dp(160))) result += rect.box()
            }
            if (depth < 12) for (i in 0 until node.childCount) {
                if (visited >= 160) break
                val child = node.getChild(i) ?: continue
                try { visit(child, depth + 1) } finally { release(child) }
            }
        }
        visit(root, 0)
        return result
    }
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        rotationUntil = SystemClock.elapsedRealtime() + 1800
        obstaclesDirty = true
        fieldStability.reset()
        reservedPosition = null
        inspect()
    }

    override fun onServiceConnected() {
        connected = this
        wm = getSystemService(WindowManager::class.java)
        offset = position.getInt("field-offset-v1", 0)
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            if (Build.VERSION.SDK_INT >= 33) flags = flags or AccessibilityServiceInfo.FLAG_INPUT_METHOD_EDITOR
        }
        scope.launch { SettingsRepository.get(this@PaplyButtonService).state.collect { inspect() } }
        scope.launch {
            while (isActive) {
                inspect()
                val active = session
                if (phase == ButtonPolicy.Phase.RECORDING && active != null) {
                    recordingWarning(active)
                    if (active.recording.interrupted || (!foreground && !active.recording.hasSignal &&
                        SystemClock.elapsedRealtime() - active.recording.startedAt > 1800)) {
                        if (!foreground && !active.speechDetected) retryForeground(active)
                        else { hint("Mikrofon belegt oder gesperrt. Aufnahme beendet."); finish() }
                    }
                }
                delay(100)
            }
        }
    }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        when (event?.eventType) {
            AccessibilityEvent.TYPE_WINDOWS_CHANGED, AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED, AccessibilityEvent.TYPE_VIEW_SCROLLED,
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> obstaclesDirty = true
        }
        inspect()
    }
    // Inspection never reads field contents; only the explicit insertion attempt does.
    private fun inspect() {
        if (!::wm.isInitialized) return
        val windows = runCatching { windows }.getOrDefault(emptyList())
        val keyboard = windows.filter { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
            .map { Rect().also(it::getBoundsInScreen) }.filter { !it.isEmpty }
        imeBounds = keyboard.map { it.box() }
        keyboardStable = keyboardStability.observe(keyboard, SystemClock.elapsedRealtime())
        keyboardTop = keyboard.minOfOrNull { it.top } ?: resources.displayMetrics.heightPixels
        val root = windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive }
            ?.root
        val next = root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        val now = SystemClock.elapsedRealtime()
        if (obstaclesDirty && now - obstaclesReadAt >= 150) {
            val collected = root?.let(::collectObstacles).orEmpty()
            if (collected != obstacles) { obstacles = collected; lastRender = null }
            obstaclesDirty = false; obstaclesReadAt = now
        }
        release(root)
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < 33) windows.forEach { it.recycle() }
        eligible = ButtonPolicy.visible(SettingsRepository.get(this).state.value.paplyButton,
            next?.isFocused == true, next?.isEditable == true, next?.isPassword == true, keyboard.isNotEmpty() &&
                getSystemService(android.os.PowerManager::class.java).isInteractive &&
                !getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        if (eligible) fieldGapUntil = now + 350
        if (next?.isPassword == true || !SettingsRepository.get(this).state.value.paplyButton) fieldGapUntil = 0
        if (!eligible) fieldStability.reset(hold = bar != null)
        else if (next != field) fieldStability.reset(hold = bar != null)
        val previousBounds = fieldBounds
        fieldBounds = next?.takeIf { it.isFocused && it.isEditable }?.let { Rect().also(it::getBoundsInScreen) }
        if (next != field || previousBounds != fieldBounds) { obstaclesDirty = true; lastRender = null }
        release(field)
        field = next
        if (now < rotationUntil && eligible && originId != null &&
            next?.viewIdResourceName == originId && next?.packageName?.toString() == originPackage) {
            release(origin)
            @Suppress("DEPRECATION")
            origin = next?.let { AccessibilityNodeInfo.obtain(it) }
        }
        val lost = !eligible || next != origin
        if (lost && missingSince == null) missingSince = now
        if (!lost) missingSince = null
        val grace = ButtonTargetGrace.waiting(now, rotationUntil, missingSince, eligible, next == origin)
        if (phase != ButtonPolicy.Phase.IDLE && (changed || (lost && !grace))) {
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
        release(origin)
        @Suppress("DEPRECATION")
        origin = field?.let { AccessibilityNodeInfo.obtain(it) }
        originId = field?.viewIdResourceName; originPackage = field?.packageName?.toString()
        missingSince = null; changed = false
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
                warning = ButtonRecordingWarning(); amber = false
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
                        if (active.limitReached) recordingWarning(active) }
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
                        if (active.limitReached) recordingWarning(active)
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
                if (connection != null) {
                    val surrounding = connection.getSurroundingText(1, 0, 0)
                    val before = surrounding?.let {
                        ButtonTextInsertion.beforeSelection(it.text, it.selectionStart, it.selectionEnd)
                    }
                    if (sameField()) {
                        connection.commitText(PaplyIme.spaced(entry.text, before), 1, null)
                        true
                    } else false
                } else false
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
        val message = ButtonPresentation.deliveryMessage(accepted, retained, copied, clipboardFallback,
            sent == ButtonTextInsertion.Result.REVIEW)
        runCatching { HistoryStore.get(this).updateIfPresent(entry.copy(
            status = if (accepted) HistoryStatus.OK else HistoryStatus.PENDING, error = message)) }
        if (message != null) hint(message)
        if (accepted) transition(ButtonPolicy.Event.SUCCESS)
    }
    private fun recordingWarning(active: DictationSession) {
        val elapsed = SystemClock.elapsedRealtime() - active.recording.startedAt
        amber = warning.amber(elapsed)
        when (warning.observe(elapsed, active.limitReached)) {
            ButtonRecordingWarning.Event.NONE -> Unit
            ButtonRecordingWarning.Event.MINUTE -> {
                logo?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                hint("Noch 1 Minute")
            }
            ButtonRecordingWarning.Event.LIMIT -> {
                logo?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                hint("10 Minuten erreicht. Dein Text wird verarbeitet.")
            }
        }
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
            message.startsWith("Text auch in der Zwischenablage") -> message
            message.startsWith("10 Minuten") -> message
            message.contains("Schlüssel", true) -> "Schlüssel fehlt oder ist ungültig"
            message.contains("Keine Sprache", true) -> "Keine Sprache erkannt. Bitte erneut versuchen."
            message.contains("belegt", true) -> "Mikrofon belegt"
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
        val safe = screenInsets()
        val safeTop = safe.top; val safeLeft = safe.left; val safeRight = safe.right
        val model = ButtonPresentation.render(phase, hintText)
        val size = dp(model.sizeDp)
        val inset = (dp(72) - size) / 2
        val bounds = fieldBounds?.takeUnless { it.isEmpty }
        val candidate = ButtonPosition.anchor(keyboardTop.coerceAtMost(screen.y), bounds?.top,
            bounds?.bottom, safeTop, dp(72), dp(8), dp(96), dp(200))
        // Hold the accepted position through a field transition; settle before moving.
        if (bounds != null) fieldStability.observe(bounds.top, SystemClock.elapsedRealtime())
        else fieldStability.reset(hold = bar != null)
        val anchor = if (bounds != null) fieldStability.top?.let {
            ButtonPosition.anchor(keyboardTop.coerceAtMost(screen.y), it, bounds.bottom,
                safeTop, dp(72), dp(8), dp(96), dp(200))
        } else candidate
        maxOffset = anchor?.let { ButtonPosition.maxOffset(it, safeTop, dp(72), dp(8)) } ?: 0
        if (anchor != null) offset = offset.coerceIn(0, maxOffset)
        val anchoredY = anchor?.let { ButtonPosition.top(it, safeTop, dp(72), dp(8), offset) }?.plus(inset)
        val persistent = phase != ButtonPolicy.Phase.IDLE || hintText != null
        val holding = bar != null && reservedPosition != null &&
            ((!eligible && SystemClock.elapsedRealtime() < fieldGapUntil) ||
                (eligible && bounds != null && fieldStability.top != null &&
                    kotlin.math.abs(fieldStability.top!! - bounds.top) > dp(4)))
        val show = !overlayFailed && (persistent || (eligible && keyboardStable && anchoredY != null) || holding)
        if (!show) {
            lastRender = null
            reservedPosition = null
            positionAnimator?.cancel(); positionAnimator = null
            bar?.let { view ->
                logo?.stopAnimation()
                bar = null
                view.animate().cancel()
                runCatching { wm.removeView(view) }
            }; return
        }
        val horizontal = ButtonPosition.horizontal(screen.x, safeLeft, safeRight, dp(8))
        val key = RenderKey(model, horizontal.rightMargin + inset, anchoredY ?: safeTop, horizontal.width, amber,
            eligible, keyboardStable, holding, imeBounds, safeTop)
        if (bar != null && key == lastRender) return
        val needsMeasure = bar == null || lastRender?.model != model || lastRender?.width != horizontal.width
        if (bar == null) {
            val view = LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
                isFocusable = false; defaultFocusHighlightEnabled = false
            }
            logo = PaplyButtonView(this).apply {
                level = { session?.recording?.level ?: 0f }
                setOnClickListener { if (phase == ButtonPolicy.Phase.IDLE) start() else if (phase == ButtonPolicy.Phase.RECORDING) finish() }
            }
            label = TextView(this).apply { setTextColor(Color.WHITE); textSize = 13f; gravity = Gravity.CENTER_VERTICAL; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(dp(8),0,dp(8),0) }
            cancel = TextView(this).apply { text = "✕"; textSize = 20f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); contentDescription = "Aufnahme verwerfen"; setOnClickListener { discard() } }
            listOfNotNull(label, cancel).forEach { it.isFocusable = false; it.defaultFocusHighlightEnabled = false }
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
                        if (dragged) { offset = (initial - (event.rawY - down).toInt()).coerceIn(0, maxOffset); render() }; true
                    }
                    MotionEvent.ACTION_UP -> { if (dragged) position.edit().putInt("field-offset-v1", offset).apply() else v.performClick(); true }
                    else -> true
                }
            }
            try { wm.addView(view, layout) } catch (_: Exception) { bar = null; overlayFailed = true; discard("Paply-Knopf kann nicht angezeigt werden. Bedienungshilfe erneut einschalten."); return }
            if (ValueAnimator.areAnimatorsEnabled()) { view.alpha = 0f; view.animate().alpha(1f).setDuration(140).start() }
        }
        logo?.setPhase(phase)
        logo?.amber = amber
        logo?.let { if (it.layoutParams.width != size) {
            it.layoutParams = LinearLayout.LayoutParams(size, size)
        } }
        label?.visibility = if (model.hint == null) View.GONE else View.VISIBLE
        cancel?.visibility = if (model.cancel) View.VISIBLE else View.GONE
        if (label?.text?.toString().orEmpty() != hintText.orEmpty()) label?.text = hintText
        val controlsWidth = size + (if (cancel?.visibility == View.VISIBLE) dp(48) else 0)
        val labelWidth = (horizontal.width - inset - controlsWidth).coerceAtLeast(0)
        if (label?.maxWidth != labelWidth) label?.maxWidth = labelWidth
        bar?.layoutDirection = View.LAYOUT_DIRECTION_LTR
        if (needsMeasure) bar?.measure(View.MeasureSpec.makeMeasureSpec((horizontal.width - inset).coerceAtLeast(0), View.MeasureSpec.AT_MOST), View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY))
        // Fix the actual window width too: a WRAP_CONTENT relayout can otherwise
        // grow beyond the measured left-anchored position on the next frame.
        val previousHeight = layout.height; val previousWidth = layout.width; val previousX = layout.x; val previousY = layout.y
        layout.width = (bar?.measuredWidth ?: size).coerceAtMost(horizontal.width)
        layout.height = size
        val placementObstacles = obstacles + imeBounds
        val reserved = if (holding) reservedPosition else if (eligible && keyboardStable && anchoredY != null)
            ButtonPosition.choose(safeLeft + dp(8), screen.x - safeRight - dp(8), safeTop,
                keyboardTop.coerceAtMost(screen.y), dp(120), dp(72), dp(8),
                bounds?.box(), placementObstacles, offset, fieldStability.top)
        else null
        reservedPosition = reserved
        val anchored = reserved?.let {
            val window = ButtonPosition.window(it, layout.width, size, dp(72))
            if (hintText == null || (window.left >= safeLeft + dp(8) &&
                    ButtonPosition.clearPath(window, window, bounds?.box(), placementObstacles))) window
            else ButtonPosition.choose(safeLeft + dp(8), screen.x - safeRight - dp(8), safeTop,
                keyboardTop.coerceAtMost(screen.y), layout.width, size, dp(8),
                bounds?.box(), placementObstacles, offset, fieldStability.top)
        }
        // Full-screen IME bounds may cover every candidate. Keep controls at safeTop,
        // never fall back to the IME's bottom-right Done/Send area.
        val target = ButtonPosition.resolve(phase, hintText != null, anchored,
            screen.x - safeRight - dp(8) - inset, safeTop, layout.width, size, dp(8))
        if (target == null) { bar?.visibility = View.INVISIBLE; lastRender = null; return }
        bar?.visibility = View.VISIBLE
        layout.x = screen.x - target.right
        layout.y = target.top
        lastRender = key
        if (layout.height != previousHeight || layout.width != previousWidth || layout.x != previousX || layout.y != previousY) {
            positionAnimator?.cancel()
            val targetX = layout.x; val targetY = layout.y
            val from = ButtonPosition.Box(screen.x - previousX - layout.width, previousY,
                screen.x - previousX, previousY + size)
            if (previousWidth > 0 && previousHeight == size && ValueAnimator.areAnimatorsEnabled() &&
                ButtonPosition.clearPath(from, target, bounds?.box(), placementObstacles)) {
                positionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = 180
                    interpolator = android.view.animation.DecelerateInterpolator()
                    addUpdateListener {
                        val fraction = it.animatedValue as Float
                        layout.x = previousX + ((targetX - previousX) * fraction).toInt()
                        layout.y = previousY + ((targetY - previousY) * fraction).toInt()
                        bar?.let { view -> runCatching { wm.updateViewLayout(view, layout) } }
                    }
                    start()
                }
            } else bar?.let { runCatching { wm.updateViewLayout(it, layout) } }
        }
    }
    private fun screenInsets(): ButtonPosition.Insets {
        if (Build.VERSION.SDK_INT >= 30) {
            val insets = wm.currentWindowMetrics.windowInsets
            val bars = insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            return ButtonPosition.safeInsets(bars.top, bars.left, bars.right, 0, 0, 0)
        }
        // API 29: overlay-local insets are not screen insets. Real display cutout + system resources.
        @Suppress("DEPRECATION") val cutout = wm.defaultDisplay.cutout
        fun dimension(name: String): Int {
            val id = resources.getIdentifier(name, "dimen", "android")
            return if (id != 0) resources.getDimensionPixelSize(id) else 0
        }
        val landscape = resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        @Suppress("DEPRECATION") val rotation = wm.defaultDisplay.rotation
        val nav = if (landscape) dimension("navigation_bar_width") else 0
        return ButtonPosition.safeInsets(dimension("status_bar_height"),
            if (rotation == Surface.ROTATION_270) nav else 0,
            if (rotation == Surface.ROTATION_90) nav else 0,
            cutout?.safeInsetTop ?: 0, cutout?.safeInsetLeft ?: 0, cutout?.safeInsetRight ?: 0)
    }
    override fun onInterrupt() {
        if (phase == ButtonPolicy.Phase.STARTING) discard("Aufnahme unterbrochen.")
        if (phase == ButtonPolicy.Phase.RECORDING) { changed = true; hint("Aufnahme unterbrochen. Text wird gesichert."); finish() } }
    override fun onDestroy() {
        connected = null; changed = true; generation++; preparing?.cancel()
        if (phase == ButtonPolicy.Phase.RECORDING) { hint("Paply-Knopf beendet. Text wird gesichert."); session?.finish() }
        stopForeground(); scope.cancel()
        logo?.stopAnimation()
        positionAnimator?.cancel()
        release(field); release(origin); field = null; origin = null
        bar?.let { runCatching { wm.removeViewImmediate(it) } }; bar = null
        super.onDestroy()
    }
}
