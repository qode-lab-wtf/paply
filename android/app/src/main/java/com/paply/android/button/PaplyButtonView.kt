package com.paply.android.button

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import com.paply.android.R
import kotlin.math.exp
import kotlin.math.sin

/** One small display-list per frame; no layouts, audio work or allocations in onDraw. */
internal class PaplyButtonView(context: Context) : View(context) {
    var amber = false
        set(value) { if (field != value) { field = value; invalidate() } }
    internal val animationRunning get() = animator?.isRunning == true
    var level: () -> Float = { 0f }
    private var phase = ButtonPolicy.Phase.IDLE
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG)
    private val arc = RectF()
    private val check = Path()
    private val mark = context.getDrawable(R.drawable.ic_paply)!!
    private val density = resources.displayMetrics.density
    private var animator: ValueAnimator? = null
    private var lastFrame = 0L
    private var time = 0f
    private var amplitude = 0f
    private var radius = 24f

    init {
        isClickable = true
        isFocusable = true
        contentDescription = "Paply-Diktat starten"
    }

    fun setPhase(value: ButtonPolicy.Phase) {
        if (phase == value) return
        phase = value
        // Every recording has fresh visual state, independent of transient hints.
        amplitude = 0f
        time = 0f
        contentDescription = when (value) {
            ButtonPolicy.Phase.IDLE -> "Paply-Diktat starten"
            ButtonPolicy.Phase.STARTING -> "Mikrofon startet"
            ButtonPolicy.Phase.RECORDING -> "Aufnahme beenden und einsetzen"
            ButtonPolicy.Phase.WORKING -> "Text wird verarbeitet"
            ButtonPolicy.Phase.SUCCESS -> "Text eingesetzt"
        }
        isClickable = value == ButtonPolicy.Phase.IDLE || value == ButtonPolicy.Phase.RECORDING
        stopAnimation()
        if (isAttachedToWindow) startAnimation()
        invalidate()
    }

    private fun startAnimation() {
        if (animator != null) return
        if (phase == ButtonPolicy.Phase.IDLE) { radius = 24f; return }
        if (!ValueAnimator.areAnimatorsEnabled()) {
            radius = if (phase == ButtonPolicy.Phase.RECORDING) 28f else 24f
            return
        }
        lastFrame = SystemClock.uptimeMillis()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 2400
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                val now = SystemClock.uptimeMillis()
                val dt = ((now - lastFrame) / 1000f).coerceIn(0f, .05f)
                lastFrame = now
                time += dt
                val target = if (phase == ButtonPolicy.Phase.RECORDING) level().coerceIn(0f, 1f) else 0f
                amplitude += (target - amplitude) * (1f - exp(-dt / .12f))
                val targetRadius = if (phase == ButtonPolicy.Phase.RECORDING) 28f else 24f
                radius += (targetRadius - radius) * (1f - exp(-dt / .10f))
                invalidate()
                if (phase == ButtonPolicy.Phase.IDLE && kotlin.math.abs(radius - 24f) < .02f) stopAnimation()
            }
            start()
        }
    }

    fun stopAnimation() {
        animator?.removeAllUpdateListeners()
        animator?.cancel()
        animator = null
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); startAnimation() }
    override fun onDetachedFromWindow() { stopAnimation(); super.onDetachedFromWindow() }
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.Button"
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.translate(width / 2f, height / 2f)
        canvas.scale(density, density)
        if (phase == ButtonPolicy.Phase.RECORDING) {
            val breath = (sin(time * 2.6f) + 1f) * .5f
            ink.color = if (amber) Color.rgb(218, 170, 75) else Color.rgb(58, 216, 121)
            ink.style = Paint.Style.STROKE
            ink.strokeWidth = 1.5f
            for (i in 0..2) {
                ink.alpha = (28 + amplitude * 70 - i * 6).toInt()
                canvas.drawCircle(0f, 0f, 29f + i * 2f + amplitude * 1.2f + breath * .6f, ink)
            }
        }
        ink.style = Paint.Style.FILL
        ink.color = Color.rgb(15, 44, 32)
        canvas.drawCircle(0f, 0f, radius, ink)
        if (phase == ButtonPolicy.Phase.SUCCESS) {
            ink.color = Color.rgb(58, 216, 121)
            ink.style = Paint.Style.STROKE
            ink.strokeWidth = 2.8f
            ink.strokeCap = Paint.Cap.ROUND
            ink.strokeJoin = Paint.Join.ROUND
            check.rewind()
            check.moveTo(-9f, 0f); check.lineTo(-2f, 7f); check.lineTo(11f, -7f)
            canvas.drawPath(check, ink)
        } else {
            mark.setBounds(-15, -15, 15, 15)
            mark.draw(canvas)
        }
        if (phase == ButtonPolicy.Phase.STARTING || phase == ButtonPolicy.Phase.WORKING) {
            ink.color = Color.rgb(58, 216, 121)
            ink.style = Paint.Style.STROKE
            ink.strokeWidth = 2f
            ink.strokeCap = Paint.Cap.ROUND
            arc.set(-29f, -29f, 29f, 29f)
            canvas.drawArc(arc, time * 150f - 90f, 100f, false, ink)
        }
        canvas.restore()
    }
}
