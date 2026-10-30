package com.paply.android.dictation

import android.os.Handler
import android.os.Looper
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import com.paply.android.PaplyIme
import com.paply.android.ImePanelState
import java.time.Duration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowInputMethodManager

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ImeAutoReturnTest {
    @Test fun onlyAcceptedTextWithConfirmationOrClipboardReturns() {
        assertTrue("Confirmed insertion", ImePolicy.returnAfterDelivery(true, true, false))
        assertTrue("Unreadable editor, clipboard backup", ImePolicy.returnAfterDelivery(true, null, true))
        assertTrue("Unconfirmed editor, clipboard backup", ImePolicy.returnAfterDelivery(true, false, true))
        assertFalse("Unknown insertion without clipboard backup", ImePolicy.returnAfterDelivery(true, null, false))
        assertFalse("Unconfirmed insertion without clipboard backup", ImePolicy.returnAfterDelivery(true, false, false))
        assertFalse("Changed field, even with earlier confirmation", ImePolicy.returnAfterDelivery(false, true, true))
        assertFalse("Pending clipboard text", ImePolicy.returnAfterDelivery(false, null, true))
        assertFalse("Pending history text", ImePolicy.returnAfterDelivery(false, null, false))
    }

    @Test fun successIsVisibleFor350MsAndReturnsOnlyOnce() {
        val returning = ImeAutoReturn(Handler(Looper.getMainLooper()))
        var switches = 0
        returning.schedule({ true }) { switches++ }
        advance(349)
        assertEquals(0, switches)
        advance(1)
        assertEquals(1, switches)
        advance(1000)
        assertEquals(1, switches)
    }

    @Test fun changedTargetOrNewSessionCannotRunAnOldReturn() {
        val returning = ImeAutoReturn(Handler(Looper.getMainLooper()))
        var current = true
        var switches = 0
        returning.schedule({ current }) { switches++ }
        advance(100)
        current = false
        advance(250)
        assertEquals(0, switches)
        returning.schedule({ true }) { fail("Replaced session switched the keyboard") }
        advance(100)
        returning.schedule({ true }) { switches++ }
        advance(250)
        assertEquals(0, switches)
        advance(100)
        assertEquals(1, switches)
    }

    @Test fun leavingOrDestroyingTheImeCancelsItsReturn() {
        for ((index, leave) in listOf<(PaplyIme) -> Unit>(
            { it.onFinishInputView(false) }, { it.onWindowHidden() },
            { it.onStartInput(EditorInfo().apply { packageName = "another.editor" }, false) }
        ).withIndex()) {
            val controller = Robolectric.buildService(PaplyIme::class.java).create()
            val ime = controller.get()
            PaplyIme::class.java.getDeclaredMethod("setPanel", ImePanelState::class.java).apply { isAccessible = true }
                .invoke(ime, ImePanelState("inserted", title = "Eingesetzt", returningToKeyboard = true))
            val returning = PaplyIme::class.java.getDeclaredField("autoReturn").apply { isAccessible = true }.get(ime) as ImeAutoReturn
            returning.schedule({ true }) { fail("IME switched after leaving the input view") }
            advance(100)
            leave(ime)
            advance(250)
            if (index == 2) {
                val panel = PaplyIme::class.java.getDeclaredMethod("getPanel").apply { isAccessible = true }.invoke(ime) as ImePanelState
                assertFalse("Cancelled return must leave the Back button available", panel.returningToKeyboard)
            }
            returning.schedule({ true }) { fail("Destroyed IME switched the keyboard") }
            controller.destroy()
            advance(350)
        }
    }

    @Test fun manualReturnCancelsTheAutomaticReturnEvenWhenSwitchingFails() {
        val controller = Robolectric.buildService(PaplyIme::class.java).create()
        val ime = controller.get()
        val returning = PaplyIme::class.java.getDeclaredField("autoReturn").apply { isAccessible = true }.get(ime) as ImeAutoReturn
        returning.schedule({ true }) { fail("Manual return caused a second keyboard switch") }
        advance(100)
        val changed = PaplyIme::class.java.getDeclaredMethod("previousKeyboard", Boolean::class.javaPrimitiveType).apply {
            isAccessible = true
        }.invoke(ime, false)
        assertEquals(false, changed)
        advance(350)
        controller.destroy()
    }

    @Test
    @Config(shadows = [PickerShadow::class])
    fun failedAutomaticSwitchOpensThePickerOnlyOnUserRequest() {
        PickerShadow.shown = 0
        val controller = Robolectric.buildService(PaplyIme::class.java).create()
        val method = PaplyIme::class.java.getDeclaredMethod("previousKeyboard", Boolean::class.javaPrimitiveType).apply { isAccessible = true }
        assertEquals(false, method.invoke(controller.get(), false))
        assertEquals(0, PickerShadow.shown)
        assertEquals(false, method.invoke(controller.get(), true))
        assertEquals(1, PickerShadow.shown)
        controller.destroy()
    }

    private fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
}

@Implements(InputMethodManager::class)
class PickerShadow : ShadowInputMethodManager() {
    @Implementation protected fun showInputMethodPicker() { shown++ }
    companion object { var shown = 0 }
}
