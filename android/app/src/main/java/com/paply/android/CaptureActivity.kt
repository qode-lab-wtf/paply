package com.paply.android

import android.animation.ValueAnimator
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.paply.android.settings.SettingsRepository
import com.paply.android.thoughts.ThoughtNotifications
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.theme.PaplyTheme
import com.paply.android.ui.thoughts.captureFeedback
import kotlinx.coroutines.*

/** Visible permission/start surface. Intent consumption survives recreation; no lifecycle auto-start. */
class CaptureActivity : ComponentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var consumed = false
    private var resumed = false
    private var pendingStart = false
    private var startWhenResumed = false
    private var notificationAsked = false
    private var notice by mutableStateOf<String?>(null)
    private var permissionGranted by mutableStateOf(false)
    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permissionGranted = hasMicrophone()
        if (pendingStart) {
            pendingStart = false
            if (permissionGranted) startCapture() else notice = "Bitte Mikrofonzugriff erlauben, um einen Gedanken aufzunehmen."
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        consumed = savedInstanceState?.getBoolean("consumed") ?: false
        notificationAsked = savedInstanceState?.getBoolean("notificationAsked") ?: false
        // A reconstructed Activity never resumes an unfinished start request.
        setShowWhenLocked(true)
        window.setGravity(Gravity.BOTTOM)
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        permissionGranted = hasMicrophone()
        setContent {
            PaplyTheme {
                val state by ThoughtState.current.collectAsState()
                val canDismiss = !ThoughtState.active || ThoughtNotifications.visible(this)
                SideEffect { setFinishOnTouchOutside(canDismiss) }
                BackHandler { dismissCard() }
                SideEffect { if (state.message.isNotBlank()) claimFeedback(state.id) }
                val feedback = captureFeedback(state.phase, notice ?: state.message,
                    requiresAction = (!permissionGranted && (notice != null || state.message.isNotBlank())) || notice == ThoughtService.BETA_OFF)
                val opacity = remember { Animatable(1f) }
                LaunchedEffect(feedback, state.id) {
                    opacity.snapTo(1f)
                    val timeout = feedback.hideAfterMs ?: return@LaunchedEffect
                    delay(timeout - 220)
                    if (ValueAnimator.areAnimatorsEnabled()) opacity.animateTo(0f, tween(220)) else delay(220)
                    dismissCard()
                    // The card owns its exit; avoid a second system-window transition.
                    @Suppress("DEPRECATION")
                    overridePendingTransition(0, 0)
                }
                CaptureCard(state, notice, feedback, canDismiss, Modifier.graphicsLayer { alpha = opacity.value }, onFinish = { ThoughtService.command(this, ThoughtService.FINISH) },
                    onDiscard = { ThoughtService.command(this, ThoughtService.DISCARD) }, onDismiss = ::dismissCard,
                    onStart = ::requestStart, onSetup = {
                        startActivity(Intent(this, MainActivity::class.java))
                        if (!ThoughtState.active) finish()
                    })
            }
        }
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        scope.launch {
            var wasActive = ThoughtState.active
            ThoughtState.current.collect {
                val active = ThoughtState.active
                if (wasActive && !active) notice = null
                wasActive = active
                setFinishOnTouchOutside(!active || ThoughtNotifications.visible(this@CaptureActivity))
            }
        }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("consumed", consumed); outState.putBoolean("notificationAsked", notificationAsked)
        super.onSaveInstanceState(outState)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent); consumed = false
        // singleTop on an already resumed card does not necessarily call onPostResume again.
        consumeAction()
    }
    override fun onPostResume() {
        super.onPostResume(); consumeAction()
        if (startWhenResumed) { startWhenResumed = false; startCapture() }
    }
    private fun consumeAction() {
        if (consumed) return
        consumed = true
        val action = intent.action
        intent.action = ThoughtService.SHOW
        if (action == ThoughtService.SHOW) return
        if (ThoughtState.active) { ThoughtService.command(this, ThoughtService.FINISH); return }
        requestStart()
    }
    private fun hasMicrophone() = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    private fun requestStart() {
        notice = null
        if (!SettingsRepository.get(this).state.value.betaThoughts) { notice = ThoughtService.BETA_OFF; return }
        val missing = mutableListOf<String>()
        if (!hasMicrophone()) missing += Manifest.permission.RECORD_AUDIO
        if (Build.VERSION.SDK_INT >= 33 && !notificationAsked && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationAsked = true; missing += Manifest.permission.POST_NOTIFICATIONS
        }
        if (missing.isNotEmpty()) { missing.forEach { com.paply.android.ui.markPermissionAsked(this, it) }; pendingStart = true; permissions.launch(missing.toTypedArray()) }
        else startCapture()
    }
    private fun startCapture() {
        if (!resumed) {
            startWhenResumed = true; return
        }
        ThoughtService.start(this)?.let { notice = it }
    }
    private fun dismissCard() {
        if (ThoughtState.active && !ThoughtNotifications.visible(this)) {
            notice = "Benachrichtigungen sind für Paply aus, darum bleibt diese Karte offen. Tippe „Fertig“ oder „Verwerfen“. Einschalten: Einstellungen → Apps → Paply."
        } else finish()
    }
    override fun finish() {
        if (ThoughtState.active && !ThoughtNotifications.visible(this)) {
            notice = "Benachrichtigungen sind für Paply aus, darum bleibt diese Karte offen. Tippe „Fertig“ oder „Verwerfen“. Einschalten: Einstellungen → Apps → Paply."; return
        }
        super.finish()
    }
    override fun onResume() { super.onResume(); resumed = true; cardVisible = true; permissionGranted = hasMicrophone() }
    override fun onPause() { resumed = false; super.onPause() }
    override fun onStop() {
        if (!isChangingConfigurations) {
            cardVisible = false
            if (ThoughtState.active) ThoughtService.command(this, ThoughtService.HIDDEN)
        }
        super.onStop()
    }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
    companion object {
        fun claimFeedback(id: String?) { feedbackOwnedId = id }
        @Volatile var feedbackOwnedId: String? = null; private set
        @Volatile var cardVisible = false; private set }
}

@Composable
private fun CaptureCard(state: ThoughtState.State, notice: String?, feedback: com.paply.android.ui.thoughts.CaptureFeedback, canDismiss: Boolean, modifier: Modifier = Modifier,
    onFinish: () -> Unit, onDiscard: () -> Unit, onDismiss: () -> Unit, onStart: () -> Unit, onSetup: () -> Unit) {
    val active = state.phase in listOf("starting", "recording", "stopping")
    Surface(modifier = modifier.fillMaxWidth().padding(10.dp), shape = RoundedCornerShape(24.dp), color = C.forestDeep,
        border = androidx.compose.foundation.BorderStroke(1.dp, C.thoughtMint.copy(alpha = .3f))) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (feedback.hideAfterMs != null) {
                Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).semantics { liveRegion = LiveRegionMode.Polite },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Glyph(if (feedback.saved) PaplyIcons.Check else PaplyIcons.Lightbulb,
                        tint = if (feedback.saved) C.greenBright else C.secondary, size = 22.dp)
                    Text(feedback.text, style = MaterialTheme.typography.bodyMedium)
                }
                return@Column
            }
            var dragged by remember { mutableFloatStateOf(0f) }
            Box(Modifier.fillMaxWidth().height(12.dp).pointerInput(canDismiss) {
                detectVerticalDragGestures(onDragStart = { dragged = 0f }, onDragEnd = { if (dragged > 35.dp.toPx()) onDismiss() }) { change, amount ->
                    dragged += amount; change.consume()
                }
            }, contentAlignment = Alignment.Center) {
                Box(Modifier.width(40.dp).height(4.dp).clip(RoundedCornerShape(2.dp)).background(C.tertiary))
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Glyph(PaplyIcons.Lightbulb, tint = C.thoughtMint, size = 20.dp)
                Text("Gedanke", style = MaterialTheme.typography.bodyMedium, color = C.secondary)
            }
            if (active) {
                val seconds = state.elapsedMs / 1000
                Text("%02d:%02d".format(seconds / 60, seconds % 60), style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Light), color = C.text)
                Text(when { state.interrupted -> "Unterbrochen · danach geht es weiter"
                    state.warnLimit -> "Noch 1 Min. · dann wird gespeichert"
                    state.phase == "starting" -> "Mikrofon startet …"
                    state.phase == "stopping" -> "Aufnahme wird gesichert …"
                    else -> "Sprich deinen Gedanken aus" }, color = if (state.interrupted || state.warnLimit) C.beak else C.secondary)
                Canvas(Modifier.fillMaxWidth().height(24.dp)) {
                    val bars = 32
                    for (i in 0 until bars) {
                        val shape = .25f + .75f * kotlin.math.abs(kotlin.math.sin(i * .8f))
                        val height = (4.dp.toPx() + size.height * state.level * shape).coerceAtMost(size.height)
                        val x = size.width * (i + .5f) / bars
                        drawLine(C.thoughtMint, Offset(x, (size.height - height) / 2), Offset(x, (size.height + height) / 2), 3.dp.toPx(), androidx.compose.ui.graphics.StrokeCap.Round)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Pill("Verwerfen", onDiscard, prominent = false, enabled = state.phase != "stopping")
                    Pill("Fertig", onFinish, enabled = state.phase != "stopping")
                }
                Text(if (canDismiss) "Nach unten wischen · Die Aufnahme läuft weiter – du siehst sie oben in der Benachrichtigung." else "Diese Karte bleibt offen, solange Benachrichtigungen aus sind.",
                    color = C.secondary, style = MaterialTheme.typography.bodySmall)
            } else {
                Text(state.message.ifBlank { "Ein Gedanke beginnt mit deinen Worten." }, color = C.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { Pill("Aufnehmen", onStart); Pill("Schließen", onDismiss, prominent = false) }
            }
            if (notice != null) { Text(notice, color = C.beak, style = MaterialTheme.typography.bodyMedium); TextButton(onClick = onSetup) { Text("Paply einrichten") } }
        }
    }
}
