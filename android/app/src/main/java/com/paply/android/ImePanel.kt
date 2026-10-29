package com.paply.android

import android.content.res.Configuration
import android.os.SystemClock
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paply.android.ui.components.PaplyIcons
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.theme.PaplyTheme
import kotlinx.coroutines.delay
import kotlin.math.*

data class ImePanelState(val phase: String = "idle", val title: String = "", val subtitle: String = "",
    val startedAt: Long = 0, val level: () -> Float = { 0f }, val canCopy: Boolean = false,
    val returningToKeyboard: Boolean = false)

@Composable
fun ImePanel(state: ImePanelState, onFinish: () -> Unit, onDiscard: () -> Unit,
    onPrimary: () -> Unit, onCopy: () -> Unit, onBack: () -> Unit) = PaplyTheme {
    val config = LocalConfiguration.current
    val landscape = config.orientation == Configuration.ORIENTATION_LANDSCAPE
    // Gboard on the 411dp-wide Pixel AVD: 336dp portrait, 260dp landscape including
    // its 48dp navigation strip. Android draws that strip OVER the IME, so reserve it.
    val height = minOf(if (landscape) 260f else 336f, config.screenHeightDp * .68f).dp
    val live = state.phase == "recording"
    val working = state.phase in listOf("working", "starting")
    val green = live || working || state.phase == "inserted"
    val ink = if (green) C.recordInk else C.text
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    val levels = remember { mutableStateListOf<Float>().apply { repeat(36) { add(0f) } } }
    LaunchedEffect(state.phase) {
        while (live || working) {
            now = SystemClock.elapsedRealtime()
            if (live) { levels.removeAt(0); levels.add(state.level()) }
            delay(40)
        }
    }
    Box(Modifier.fillMaxWidth().height(height).background(C.forestDeep).padding(bottom = 48.dp).padding(6.dp)) {
        Column(Modifier.fillMaxSize().clip(RoundedCornerShape(18.dp))
            .background(Brush.verticalGradient(if (green) listOf(C.recordTop, C.recordBottom) else listOf(C.forest, C.forestDeep)))
            .pointerInput(state.phase) {
                var distance = 0f
                detectHorizontalDragGestures(onDragStart = { distance = 0f }, onHorizontalDrag = { change, dx -> distance += dx; change.consume() },
                    onDragEnd = { if (distance < -70.dp.toPx()) onDiscard() })
            }
            .then(if (live) Modifier.pointerInput(Unit) { detectTapGestures { onFinish() } } else Modifier)
            .padding(horizontal = 18.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (live || working) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Icon(PaplyIcons.Mic, null, tint = ink, modifier = Modifier.size(19.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (live) "Paply hört zu" else if (state.phase == "starting") "Paply wird bereit …" else "Paply schreibt …", color = ink, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Spacer(Modifier.weight(1f))
                    if (live) {
                        val seconds = (now - state.startedAt).coerceAtLeast(0) / 1000
                        Text("%d:%02d".format(seconds / 60, seconds % 60), color = ink, fontWeight = FontWeight.SemiBold,
                            style = MaterialTheme.typography.titleLarge)
                    }
                }
                Canvas(Modifier.fillMaxWidth().weight(1f).padding(vertical = 16.dp)
                    .semantics { contentDescription = if (live) "Wellenform. Tippen beendet die Aufnahme." else "Diktat wird verarbeitet." }) {
                    val time = now / 1000.0
                    val gap = 4.dp.toPx()
                    val width = (size.width - gap * 35) / 36
                    repeat(36) { i ->
                        val position = i / 35.0
                        val value = if (live) max(0.06 + 0.035 * sin(time * 2.8 + i * .42), levels[i].toDouble())
                        else {
                            val envelope = exp(-(position - .5).pow(2) / .07)
                            val shimmer = exp(-(position - ((time / 1.6) % 1.0)).pow(2) / .009)
                            (.07 + .26 * shimmer) * envelope
                        }
                        val h = max(4.dp.toPx(), size.height * value.coerceIn(0.0, 1.0).toFloat())
                        drawRoundRect(ink.copy(alpha = .83f), Offset(i * (width + gap), (size.height - h) / 2), Size(width, h), CornerRadius(2.5.dp.toPx()))
                    }
                }
                Text(if (state.subtitle.isNotBlank()) state.subtitle else if (live) "Tippen = fertig  ·  ← wischen = verwerfen" else if (now - state.startedAt > 6000) "Dauert etwas länger …" else "Wird poliert",
                    color = ink.copy(alpha = .65f), fontSize = 13.sp)
            } else {
                Spacer(Modifier.weight(1f))
                if (state.phase == "inserted") Icon(PaplyIcons.Check, null, tint = ink, modifier = Modifier.size(36.dp))
                Text(state.title.ifBlank { "Paply ist bereit" }, color = ink, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                if (state.subtitle.isNotBlank()) Text(state.subtitle, color = ink.copy(alpha = .72f), fontSize = 14.sp,
                    modifier = Modifier.padding(top = 6.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (state.phase in listOf("setup", "key", "storage", "audioMissing", "error", "pending")) Button(onClick = onPrimary,
                        colors = ButtonDefaults.buttonColors(containerColor = C.greenBright, contentColor = C.forest)) {
                        Text(when (state.phase) { "setup", "key" -> "Paply einrichten"; "audioMissing" -> "Neu aufnehmen"; "pending" -> "Einsetzen"; else -> "Erneut versuchen" })
                    }
                    if (state.canCopy && !state.returningToKeyboard) TextButton(onClick = onCopy) { Text("In Zwischenablage", color = ink) }
                }
                if (!state.returningToKeyboard) TextButton(onClick = onBack) {
                    Icon(PaplyIcons.Keyboard, null, Modifier.size(18.dp), tint = ink.copy(alpha = .7f))
                    Spacer(Modifier.width(8.dp)); Text("Zurück zur Tastatur", color = ink.copy(alpha = .7f))
                }
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
