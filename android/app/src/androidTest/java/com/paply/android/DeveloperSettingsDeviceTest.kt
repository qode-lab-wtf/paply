package com.paply.android

import android.content.Intent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import androidx.compose.runtime.*
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.settings.SettingsRepository
import com.paply.android.ui.DeveloperScreen
import com.paply.android.ui.theme.PaplyTheme
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** Device-level component test of the real developer screen and persisted settings. */
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
        while (!node.isClickable) node = requireNotNull(node.parent)
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
            instrumentation.runOnMainSync {
                activity.setContent {
                    PaplyTheme {
                        val prefs by repository.state.collectAsState()
                        val scope = rememberCoroutineScope()
                        var route by remember { mutableStateOf("developer") }
                        if (route == "developer") DeveloperScreen(prefs,
                            { transform -> scope.launch { repository.update(transform) } },
                            { route = it })
                        else Text(route, modifier = Modifier.safeDrawingPadding())
                    }
                }
            }
            assertNotNull(find("Polieren"))
            click("Polieren")
            find("Polieren")
            assertFalse(repository.snapshot().polish)
            click("Entwicklerbereich ausblenden")
            assertNotNull(find("settings"))
            assertFalse(repository.state.value.developerMode)
            assertNull(find("Polieren"))
        } finally {
            repository.update { original }
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
