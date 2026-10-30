package com.paply.android

import android.content.Intent
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.thoughts.CaptureBar
import com.paply.android.ui.thoughts.ThoughtsActions
import org.junit.Assert.*
import org.junit.Test

/** Layout-only test. Synthetic insets cover hidden, gesture and button navigation without changing system settings. */
class NavigationInsetsDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun bounds(text: String): Rect {
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(100, 5000)
        fun find(node: AccessibilityNodeInfo): Rect? {
            if (node.text?.toString() == text) return Rect().also { node.getBoundsInScreen(it) }
            for (index in 0 until node.childCount) node.getChild(index)?.let { find(it)?.let { bounds -> return bounds } }
            return null
        }
        return requireNotNull(find(requireNotNull(instrumentation.uiAutomation.rootInActiveWindow))) { "Missing $text" }
    }

    @Test fun imeAndCaptureFollowChangingInsetsAndDoNotDoublePadConsumedInsets() {
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val bottom = mutableIntStateOf(0)
        val consumed = mutableIntStateOf(0)
        val capture = mutableStateOf(false)
        val previous = ThoughtState.current.value
        try {
            instrumentation.runOnMainSync {
                ThoughtState.current.value = ThoughtState.State("recording", id = "insets-test")
                activity.setContent {
                    val repository = remember { ThoughtsRepository.get(context) }
                    val scope = rememberCoroutineScope()
                    val actions = remember { ThoughtsActions(repository, context, scope, SnackbarHostState()) }
                    Box(Modifier.fillMaxSize().consumeWindowInsets(WindowInsets(bottom = consumed.intValue)), contentAlignment = Alignment.BottomCenter) {
                        if (capture.value) CaptureBar(repository, actions, {}, WindowInsets(bottom = bottom.intValue), {})
                        else ImePanel(ImePanelState(title = "Insets-Test"), {}, {}, {}, {}, {}, WindowInsets(bottom = bottom.intValue))
                    }
                }
            }
            val originalIme = bounds("Insets-Test")
            instrumentation.runOnMainSync { bottom.intValue = 80 }
            val insetIme = bounds("Insets-Test")
            assertTrue("IME content must move above the navigation area", insetIme.top < originalIme.top)
            instrumentation.runOnMainSync { consumed.intValue = 80 }
            assertEquals("Consumed parent insets must not be added again", originalIme.top, bounds("Insets-Test").top)
            instrumentation.runOnMainSync { bottom.intValue = 0; consumed.intValue = 0; capture.value = true }
            val originalCapture = bounds("Fertig")
            for (inset in listOf(24, 48, 80, 0)) {
                instrumentation.runOnMainSync { bottom.intValue = inset }
                assertEquals("CaptureBar uses actual inset pixels", originalCapture.top - inset, bounds("Fertig").top)
            }
            instrumentation.runOnMainSync { bottom.intValue = 80; consumed.intValue = 80 }
            assertEquals(originalCapture.top, bounds("Fertig").top)
        } finally {
            instrumentation.runOnMainSync { ThoughtState.current.value = previous; activity.finish() }
        }
    }
}
