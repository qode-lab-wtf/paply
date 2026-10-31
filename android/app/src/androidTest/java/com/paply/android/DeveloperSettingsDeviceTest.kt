package com.paply.android

import android.content.Intent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.settings.SettingsRepository
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** Exercises the actual settings UI and its persisted developer preferences. */
class DeveloperSettingsDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private fun find(text: String): AccessibilityNodeInfo? {
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.waitForIdle(100, 5000)
        fun visit(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.text?.toString() == text || node.contentDescription?.toString() == text) return node
            for (i in 0 until node.childCount) node.getChild(i)?.let { visit(it)?.let { found -> return found } }
            return null
        }
        return instrumentation.uiAutomation.rootInActiveWindow?.let(::visit)
    }

    private fun click(text: String) {
        var node = requireNotNull(find(text)) { "Missing $text" }
        while (!node.isClickable) node = requireNotNull(node.parent) { "Not clickable: $text" }
        assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
    }

    @Test fun developerPolishSwitchAndHidePersist() = runBlocking {
        val context = instrumentation.targetContext
        val repository = SettingsRepository.get(context)
        val original = repository.state.value
        repository.update { it.copy(developerMode = true, polish = true) }
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try {
            click("Einstellungen")
            click("Entwicklerbereich")
            assertNotNull(find("Polieren"))
            click("Polieren")
            find("Polieren")
            assertFalse(repository.snapshot().polish)
            click("Entwicklerbereich ausblenden")
            assertNotNull(find("Einstellungen"))
            assertFalse(repository.state.value.developerMode)
            assertNull(find("Entwicklerbereich"))
        } finally {
            repository.update { original }
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
