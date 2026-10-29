package com.paply.android.button

import android.Manifest
import android.app.UiAutomation
import android.content.*
import android.provider.Settings
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.settings.SettingsRepository
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Prepared only. Explicit opt-in and externally injected speech; never synthetic product audio. */
class ButtonDeviceTest {
    @Test fun foreignEditorWithRealMicrophone() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Bauleitung only", args.getString("paplyButtonAcceptance") == "yes")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val ui = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        ui.serviceInfo = ui.serviceInfo.apply { flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS }
        val resolver = context.contentResolver
        val prefs = SettingsRepository.get(context)
        val previousPrefs = prefs.state.value
        ui.adoptShellPermissionIdentity(Manifest.permission.WRITE_SECURE_SETTINGS, "android.permission.GRANT_RUNTIME_PERMISSIONS")
        val services = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        val enabled = Settings.Secure.getInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
        try {
            ui.grantRuntimePermission(context.packageName, Manifest.permission.RECORD_AUDIO)
            prefs.update { it.copy(paplyButton = true, buttonForeground = args.getString("microphone") == "fgs") }
            val component = ComponentName(context, PaplyButtonService::class.java).flattenToString()
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                (services.orEmpty().split(':').filter { it.isNotBlank() } + component).distinct().joinToString(":"))
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            context.startActivity(Intent().setComponent(ComponentName("com.paply.android.test", "com.paply.android.ImeFixtureActivity"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            fun find(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
                fun walk(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
                    if (node == null) return null
                    if (predicate(node)) return node
                    for (i in 0 until node.childCount) walk(node.getChild(i))?.let { return it }
                    return null
                }
                return ui.windows.firstNotNullOfOrNull { walk(it.root) }
            }
            fun waitFor(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
                repeat(200) { find(predicate)?.let { return it }; Thread.sleep(100) }
                error("UI condition missing")
            }
            val field = waitFor { it.hintText?.toString() == "Erstes Textfeld" }
            assertTrue(field.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val button = waitFor { it.contentDescription?.toString() == "Paply-Diktat starten" }
            assertTrue(button.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            waitFor { it.text?.contains("· Fertig") == true }
            // Bauleitung injects its known WAV now, after audio.start, via the authorized host.
            Thread.sleep(12_000)
            val pill = waitFor { it.text?.contains("· Fertig") == true }
            assertTrue(pill.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val expected = requireNotNull(args.getString("expected")) { "expected token required" }
            waitFor { it.isEditable && it.text?.contains(expected, ignoreCase = true) == true }
        } finally {
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, services)
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, enabled)
            prefs.update { previousPrefs }
            ui.dropShellPermissionIdentity()
        }
    }
}
