package com.paply.android.button
import android.content.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [30,34])
class ButtonClipboardTest {
    private val manager get() = RuntimeEnvironment.getApplication().getSystemService(ClipboardManager::class.java)
    @Test fun explicitFallbackRetainsDictationForManualPaste() {
        manager.setPrimaryClip(ClipData.newPlainText("old", "alt"))
        assertTrue(ButtonClipboard(manager).paste("neu", {true}, {error("must retain")}, retain = true))
        assertEquals("neu", manager.primaryClip!!.getItemAt(0).text)
    }
    @Test fun restoresOpaqueClipOnlyAfterPaste() {
        val old = ClipData.newPlainText("vorher", "alt")
        manager.setPrimaryClip(old)
        var restore: (() -> Unit)? = null
        assertTrue(ButtonClipboard(manager).paste("neu", {true}, {restore = it}))
        assertEquals("neu", manager.primaryClip!!.getItemAt(0).text)
        restore!!()
        assertEquals("alt", manager.primaryClip!!.getItemAt(0).text)
    }
    @Test fun neverOverwritesNewForeignClip() {
        var restore: (() -> Unit)? = null
        ButtonClipboard(manager).paste("neu", {true}, {restore = it})
        manager.setPrimaryClip(ClipData.newPlainText("fremd", "behalten"))
        restore!!()
        assertEquals("behalten", manager.primaryClip!!.getItemAt(0).text)
    }
    @Test fun restoresEmptyAndKeepsRejectedTextForManualPaste() {
        manager.clearPrimaryClip()
        var restore: (() -> Unit)? = null
        ButtonClipboard(manager).paste("neu", {true}, {restore = it}); restore!!()
        assertFalse(manager.hasPrimaryClip())
        assertFalse(ButtonClipboard(manager).paste("manuell", {false}, {error("must not restore")}))
        assertEquals("manuell", manager.primaryClip!!.getItemAt(0).text)
    }
}
