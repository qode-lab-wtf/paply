package com.paply.android.button

import androidx.test.platform.app.InstrumentationRegistry
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import org.junit.Assert.*
import org.junit.Test

class ButtonVisualDeviceTest {
    @Test fun repeatedRoundsKeepRecordingVisibleAndAccessible() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val view = PaplyButtonView(instrumentation.targetContext)
            val size = (72 * view.resources.displayMetrics.density).toInt()
            view.layout(0, 0, size, size)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            var phase = ButtonPolicy.Phase.IDLE
            fun step(event: ButtonPolicy.Event) {
                phase = ButtonPolicy.next(phase, event)
                view.setPhase(phase)
            }
            repeat(3) { round ->
                step(ButtonPolicy.Event.START)
                step(ButtonPolicy.Event.READY)
                assertEquals("Aufnahme beenden und einsetzen", view.contentDescription)
                assertTrue(view.isClickable)
                assertEquals(View.VISIBLE, view.visibility)
                assertEquals(1f, view.alpha)
                view.draw(canvas)
                assertTrue(bitmap.getPixel(size / 2, size / 2) != 0)
                if (round == 1) step(ButtonPolicy.Event.DISCARD)
                else {
                    step(ButtonPolicy.Event.FINISH)
                    assertFalse(view.isClickable)
                    step(ButtonPolicy.Event.SUCCESS)
                    assertEquals("Text eingesetzt", view.contentDescription)
                    step(ButtonPolicy.Event.RESULT)
                }
                assertEquals("Paply-Diktat starten", view.contentDescription)
            }
            view.stopAnimation()
            bitmap.recycle()
        }
    }
}
