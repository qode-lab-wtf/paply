package com.paply.android.ui.thoughts

import android.animation.ValueAnimator
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.ThoughtService
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import kotlinx.coroutines.delay
import kotlin.math.*

@Composable
fun CaptureBar(repository: ThoughtsRepository, actions: ThoughtsActions, onCapture: () -> Unit,
    navigationInsets: WindowInsets = WindowInsets.navigationBars, onOpen: (String) -> Unit) {
    val state by repository.recording.collectAsStateWithLifecycle()
    val active = state.phase in listOf("starting", "recording", "stopping")
    val feedback = captureFeedback(state.phase, state.message)
    var transient by remember { mutableStateOf(false) }
    LaunchedEffect(feedback, state.id) {
        transient = feedback.hideAfterMs != null && !com.paply.android.CaptureActivity.cardVisible &&
            state.id != com.paply.android.CaptureActivity.feedbackOwnedId
        feedback.hideAfterMs?.let { delay(it); transient = false }
    }
    if (!active && !transient) return
    Surface(shape = CircleShape, color = C.forest, border = BorderStroke(.5.dp, C.thoughtMint.copy(alpha=.2f)),
        shadowElevation = 10.dp, modifier = Modifier.fillMaxWidth().windowInsetsPadding(navigationInsets).padding(horizontal = 12.dp, vertical = 6.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).clickable {
            if (active) onCapture() else state.id?.let(onOpen)
        }.padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (feedback.saved) Glyph(PaplyIcons.Check, tint = C.greenBright, size = 22.dp)
            else EchoOrb(30.dp, state.level, active)
            Text(buildAnnotatedString {
                if (active) {
                    append("Gedanke")
                    withStyle(SpanStyle(color = C.tertiary)) { append(" · ") }
                    withStyle(SpanStyle(color = C.secondary)) { append(clock(state.elapsedMs / 1000)) }
                } else append(feedback.text)
            }, style = MaterialTheme.typography.titleSmall.copy(fontFeatureSettings = "tnum"),
                modifier = Modifier.weight(1f), color = if (state.interrupted) C.beak else C.text)
            if (active) Pill("Fertig", { actions.run { repository.finishRecording() } }, enabled = state.phase != "stopping")
        }
    }
}

/** Compact iOS Echo: the same two clouds, level smoothing and 760 ms echo rings. */
@Composable
fun EchoOrb(size: Dp, level: Float = 0f, live: Boolean = false) {
    val reduce = !ValueAnimator.areAnimatorsEnabled()
    val target by rememberUpdatedState(level)
    val engine = remember { EchoEngine() }
    var frame by remember { mutableLongStateOf(0L) }
    LaunchedEffect(live, reduce) {
        if (live) while (true) {
            withFrameMillis { engine.step(target.toDouble(), it.toDouble(), reduce); frame = it }
            if (reduce) delay(33)
        }
    }
    val breathing = live && level <= .1f && !reduce
    val breathe = if (breathing) {
        val transition = rememberInfiniteTransition(label = "echo-breathe")
        val value by transition.animateFloat(1f, 1.03f,
            infiniteRepeatable(tween(2400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "echo-scale")
        value
    } else 1f
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(size)) {
        if (live) {
            Canvas(Modifier.requiredSize(size * 1.75f).blur(maxOf(1.dp, size * .03f), BlurredEdgeTreatment.Unbounded)) {
                val time = frame.toDouble()
                val radius = size.toPx() / 2
                fun cloud(path: Path, scale: Double, degrees: Double, color: Color) {
                    withTransform({
                        translate(center.x, center.y)
                        rotate(degrees.toFloat(), Offset.Zero)
                        scale(radius * scale.toFloat(), radius * scale.toFloat(), Offset.Zero)
                    }) { drawPath(path, color, blendMode = BlendMode.Plus) }
                }
                cloud(EchoEngine.blobB, if (reduce) 1.0 else 1 + engine.smooth * .36,
                    if (reduce) 0.0 else -time * .032 % 360, C.thoughtGold.copy(alpha = (.1 + engine.smooth * .12).toFloat()))
                cloud(EchoEngine.blobA, 1 + engine.smooth * if (reduce) .18 else .5,
                    if (reduce) 0.0 else time * .045 % 360, C.thoughtMint.copy(alpha = (.13 + engine.smooth * .15).toFloat()))
            }
            Canvas(Modifier.requiredSize(size * 1.75f)) {
                val time = frame.toDouble()
                engine.rings.forEach { start ->
                    val eased = EchoEngine.ease(((time - start) / 760).coerceIn(0.0, 1.0).toFloat())
                    drawCircle(C.thoughtMint.copy(alpha = .7f * (1 - eased)),
                        radius = size.toPx() / 2 * (1 + .62f * eased),
                        style = Stroke(maxOf(1.25.dp.toPx(), size.toPx() / 110)))
                }
            }
        }
        Box(Modifier.size(size).graphicsLayer { scaleX = breathe; scaleY = breathe }
            .shadow(size * .12f, CircleShape, clip = false).background(C.forest, CircleShape)
            .border(maxOf(.75.dp, size / 220), Color.White.copy(alpha = .12f), CircleShape), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = .17f), Color.White.copy(alpha = .03f)),
                    center = Offset(this.size.width * .5f, this.size.height * .25f), radius = this.size.width * .62f))
            }
            PaplyMark(Modifier.size(size * .4f, size * .43f).offset(x = size * -.01f))
        }
    }
}

private class EchoEngine {
    var smooth = 0.0
        private set
    val rings = mutableListOf<Double>()
    private var last: Double? = null
    private var lastRing = -10_000.0
    fun step(level: Double, time: Double, reduce: Boolean) {
        val target = level.coerceIn(0.0, 1.0)
        val dt = last?.let { (time - it).coerceIn(0.0, 100.0) } ?: 16.67
        last = time
        smooth += (target - smooth) * (1 - (1 - if (target > smooth) .5 else .14).pow(dt / 16.67))
        rings.removeAll { time - it > 760 }
        if (!reduce && smooth > .58 && time - lastRing > 420 && rings.size < 3) {
            lastRing = time; rings += time
        }
    }
    companion object {
        val blobA = blob(.4)
        val blobB = blob(2.2)
        private val ringEase = CubicBezierEasing(.2f, .7f, .3f, 1f)
        fun ease(value: Float) = ringEase.transform(value)
        private fun blob(seed: Double): Path {
            val points = List(48) { i ->
                val angle = i / 48.0 * PI * 2
                val radius = 1 + .09 * sin(3 * angle + seed) + .05 * sin(5 * angle + seed * 2.1) + .03 * sin(7 * angle)
                Offset((cos(angle) * radius).toFloat(), (sin(angle) * radius).toFloat())
            }
            return Path().apply {
                moveTo(points[0].x, points[0].y)
                points.indices.forEach { i ->
                    val p0 = points[(i + 47) % 48]; val p1 = points[i]
                    val p2 = points[(i + 1) % 48]; val p3 = points[(i + 2) % 48]
                    val c1 = p1 + (p2 - p0) / 6f; val c2 = p2 - (p3 - p1) / 6f
                    cubicTo(c1.x, c1.y, c2.x, c2.y, p2.x, p2.y)
                }
                close()
            }
        }
    }
}
