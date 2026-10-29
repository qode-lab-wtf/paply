package com.paply.android.button

import android.animation.ValueAnimator
import android.content.Intent
import android.widget.FrameLayout
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class ButtonVisualDeviceTest {
    @Test fun attachedViewStopsAnimatorBetweenRecordingRoundsAndOnRemoval() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val intent = Intent(instrumentation.targetContext, com.paply.android.MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val activity = instrumentation.startActivitySync(intent)
        try {
            instrumentation.runOnMainSync {
                val parent = FrameLayout(activity)
                activity.setContentView(parent)
                val view = PaplyButtonView(activity)
                parent.addView(view, FrameLayout.LayoutParams(144, 144))
                assertTrue(view.isAttachedToWindow)
                assertFalse(view.isFocusable)
                assertFalse(view.defaultFocusHighlightEnabled)
                assertTrue(view.isImportantForAccessibility)
                assertFalse(view.animationRunning)
                repeat(3) { round ->
                    view.setPhase(ButtonPolicy.Phase.RECORDING)
                    assertEquals(ValueAnimator.areAnimatorsEnabled(), view.animationRunning)
                    assertEquals("Aufnahme beenden und einsetzen", view.contentDescription)
                    assertTrue(view.isClickable)
                    if (round != 1) {
                        view.setPhase(ButtonPolicy.Phase.WORKING)
                        assertFalse(view.isClickable)
                        view.setPhase(ButtonPolicy.Phase.SUCCESS)
                        assertEquals("Text eingesetzt", view.contentDescription)
                    }
                    view.setPhase(ButtonPolicy.Phase.IDLE)
                    assertFalse(view.animationRunning)
                }
                view.setPhase(ButtonPolicy.Phase.RECORDING)
                parent.removeView(view)
                assertFalse(view.animationRunning)
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
}
