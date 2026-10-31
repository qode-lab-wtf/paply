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
    var onRight = true
        set(value) { field = value; invalidate() }
    var settled: () -> Unit = {}
    internal var expanding = false; private set
    private var morph = 0f
    private var morphAnimator: ValueAnimator? = null
    private val shape = Path()
    private val radii = FloatArray(8)
    private var touched = false
    private var awakeAt = 0L
    fun touching(value: Boolean) { touched = value; wake() }
    private val dim = Runnable {
        val target = ButtonPresentation.idleAlpha(phase, touched, SystemClock.uptimeMillis() - awakeAt)
        if (target < 1f) {
            if (ValueAnimator.areAnimatorsEnabled()) animate().alpha(target).setDuration(ButtonPresentation.DIM_DURATION).start()
            else alpha = target
        }
    }
    fun wake() {
        awakeAt = SystemClock.uptimeMillis()
        removeCallbacks(dim); animate().cancel(); alpha = 1f
        if (phase == ButtonPolicy.Phase.IDLE && !touched) postDelayed(dim, ButtonPresentation.DIM_DELAY)
    }
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

    init {
        isClickable = true
        isFocusable = false
        defaultFocusHighlightEnabled = false
        contentDescription = "Paply-Diktat starten"
    }

    fun setPhase(value: ButtonPolicy.Phase) {
        if (phase == value) return
        val wasIdle = phase == ButtonPolicy.Phase.IDLE
        phase = value
        wake()
        if (wasIdle != (value == ButtonPolicy.Phase.IDLE)) {
            morphAnimator?.removeAllListeners(); morphAnimator?.cancel()
            val target = if (value == ButtonPolicy.Phase.IDLE) 0f else 1f
            expanding = true
            if (ValueAnimator.areAnimatorsEnabled()) {
                morphAnimator = ValueAnimator.ofFloat(morph, target).apply {
                    duration = 220
                    interpolator = android.view.animation.DecelerateInterpolator()
                    addUpdateListener { morph = it.animatedValue as Float; invalidate() }
                    addListener(object : android.animation.AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: android.animation.Animator) {
                            expanding = false; settled()
                        }
                    })
                    start()
                }
            } else { morph = target; expanding = false }
        }
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
        if (phase == ButtonPolicy.Phase.IDLE) return
        if (!ValueAnimator.areAnimatorsEnabled()) {
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
                invalidate()
            }
            start()
        }
    }

    fun stopAnimation() {
        animator?.removeAllUpdateListeners()
        animator?.cancel()
        animator = null
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); startAnimation(); wake() }
    override fun onDetachedFromWindow() { stopAnimation(); morphAnimator?.removeAllListeners(); morphAnimator?.cancel(); removeCallbacks(dim); animate().cancel(); super.onDetachedFromWindow() }
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.Button"
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        val center = ButtonPresentation.logoCenter(width / density, morph, onRight)
        canvas.translate(center * density, height / 2f)
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
        val halfWidth = 12f + 16f * morph
        val halfHeight = 22f + 6f * morph
        arc.set(-halfWidth, -halfHeight, halfWidth, halfHeight)
        for (i in radii.indices) {
            val inner = if (onRight) i < 2 || i >= 6 else i in 2..5
            radii[i] = if (inner) halfHeight else 28f * morph
        }
        shape.rewind(); shape.addRoundRect(arc, radii, Path.Direction.CW)
        canvas.drawPath(shape, ink)
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
            val markSize = (8 + 7 * morph).toInt()
            mark.setBounds(-markSize, -markSize, markSize, markSize)
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
