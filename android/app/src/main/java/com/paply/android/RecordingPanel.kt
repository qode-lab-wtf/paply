package com.paply.android

import android.content.Context
import android.graphics.*
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.sin

/** Quiet, large recording surface mirroring the iOS PanelView interaction. */
class RecordingPanel(context: Context) : View(context) {
    var level: () -> Float = { 0f }
    var startedAt = SystemClock.elapsedRealtime()
    var onFinish: () -> Unit = {}
    var onDiscard: () -> Unit = {}
    var onDismiss: (() -> Unit)? = null
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL) }
    private var gradient: LinearGradient? = null
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        gradient = LinearGradient(0f, 0f, 0f, h.toFloat(), Brand.recordTop, Brand.green, Shader.TileMode.CLAMP)
    }
    private var downX = 0f; private var downY = 0f
    init { isClickable = true; isFocusable = true; contentDescription = "Paply hört zu. Tippen: Fertig. Nach links wischen: Verwerfen." }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize(context.dp(260), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat(); val d = resources.displayMetrics.density
        paint.shader = gradient
        canvas.drawRoundRect(0f, 0f, w, h, 20*d, 20*d, paint); paint.shader = null
        paint.color = Brand.recordInk; paint.textSize = 17*d
        canvas.drawText("Paply hört zu", 22*d, 40*d, paint)
        val seconds = (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0) / 1000
        val time = "%02d:%02d".format(seconds / 60, seconds % 60)
        paint.textAlign = Paint.Align.RIGHT; canvas.drawText(time, w-22*d, 40*d, paint)
        paint.textAlign = Paint.Align.CENTER
        val amplitude = level()
        for (i in 0..40) {
            val x = w/2 + (i-20)*6*d
            val bar = 3*d + amplitude * 50*d * (0.3f + 0.7f * abs(sin(i*0.8 + seconds*0.4)).toFloat())
            canvas.drawRoundRect(x-1.5f*d, h/2-bar, x+1.5f*d, h/2+bar, 2*d, 2*d, paint)
        }
        paint.textSize = 13*d
        canvas.drawText("Tippen: fertig · Links wischen: verwerfen", w/2, h-28*d, paint)
        paint.textAlign = Paint.Align.LEFT
        postInvalidateDelayed(80)
    }
    override fun performClick(): Boolean { super.performClick(); onFinish(); return true }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when(event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = event.x; downY = event.y; return true }
            MotionEvent.ACTION_UP -> {
                val dx = event.x-downX; val dy = event.y-downY
                if (dx < -context.dp(70) && abs(dx) > abs(dy)) onDiscard()
                else if (dy > context.dp(65) && abs(dy) > abs(dx) && onDismiss != null) onDismiss?.invoke()
                else if (abs(dx) < context.dp(16) && abs(dy) < context.dp(16)) performClick()
                return true
            }
            MotionEvent.ACTION_CANCEL -> return true
        }
        return true
    }
}
