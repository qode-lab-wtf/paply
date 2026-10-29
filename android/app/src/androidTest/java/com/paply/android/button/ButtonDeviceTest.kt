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

import org.junit.Test

/** Prepared only. Explicit opt-in and externally injected speech; never synthetic product audio. */
class ButtonDeviceTest {
    @Test fun foreignEditorWithRealMicrophone() { exercise("insert") }
    @Test fun fieldChangeDuringRecording() { exercise("field") }
    @Test fun rotateDuringRecording() { exercise("rotate") }
    @Test fun dragRemainsAboveKeyboard() { exercise("drag") }
    @Test fun rejectingEditor() { exercise("reject") }
    @Test fun pasteRestoresClipboard() { exercise("paste") }

    private fun exercise(scenario: String) { runBlocking {
        val args = InstrumentationRegistry.getArguments()
        require(args.getString("paplyButtonAcceptance") == "yes") { "Explicit Bauleitung opt-in required" }
        val expected = requireNotNull(args.getString("expected")).split('|').map(String::trim).filter(String::isNotEmpty)
        require(expected.isNotEmpty()) { "expected token required" }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val ui = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        ui.serviceInfo = ui.serviceInfo.apply { flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS }
        val resolver = context.contentResolver
        val prefs = SettingsRepository.get(context)
        val previousPrefs = prefs.state.value
        val previousHistory = com.paply.android.history.HistoryStore.get(context).entries.value.map { it.id }.toSet()
        ui.adoptShellPermissionIdentity(Manifest.permission.WRITE_SECURE_SETTINGS, "android.permission.GRANT_RUNTIME_PERMISSIONS")
        val services = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        val enabled = Settings.Secure.getInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
        try {
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, "")
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
            repeat(100) { if (PaplyButtonService.connected != null) Thread.sleep(50) }
            assertNull("Service must be disconnected before setup", PaplyButtonService.connected)
            ui.executeShellCommand("am force-stop com.paply.android.test").use { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).readBytes() }
            ui.grantRuntimePermission(context.packageName, Manifest.permission.RECORD_AUDIO)
            prefs.update { it.copy(paplyButton = true, buttonForeground = args.getString("microphone") == "fgs") }
            val component = ComponentName(context, PaplyButtonService::class.java).flattenToString()
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                (services.orEmpty().split(':').filter { it.isNotBlank() } + component).distinct().joinToString(":"))
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            context.startActivity(Intent().setComponent(ComponentName("com.paply.android.test", "com.paply.android.ImeFixtureActivity"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
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
            if (scenario == "paste") require(android.os.Build.VERSION.SDK_INT < 33) { "Paste acceptance requires API 30–32" }
            val field = waitFor { it.hintText?.toString() == if (scenario == "reject") "Editor lehnt Einsetzen ab" else "Erstes Textfeld" }
            assertTrue(field.text.isNullOrEmpty())
            assertTrue(field.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val button = waitFor { it.contentDescription?.toString() == "Paply-Diktat starten" }
            fun bounds(node: AccessibilityNodeInfo) = android.graphics.Rect().also(node::getBoundsInScreen)
            fun aboveKeyboard() {
                val b = bounds(waitFor { it.contentDescription?.toString() == "Paply-Diktat starten" }.parent)
                val ime = ui.windows.filter { it.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD }
                    .map { android.graphics.Rect().also(it::getBoundsInScreen) }.minOf { it.top }
                assertTrue("Button overlaps IME: $b / $ime", b.bottom <= ime - (8 * context.resources.displayMetrics.density).toInt())
            }
            aboveKeyboard()
            if (scenario == "drag") {
                val b = bounds(button.parent)
                val x = b.centerX().toFloat(); val y = b.centerY().toFloat(); val time = android.os.SystemClock.uptimeMillis()
                for ((action, yy) in listOf(android.view.MotionEvent.ACTION_DOWN to y, android.view.MotionEvent.ACTION_MOVE to y + 400, android.view.MotionEvent.ACTION_UP to y + 400)) {
                    val event = android.view.MotionEvent.obtain(time, android.os.SystemClock.uptimeMillis(), action, x, yy, 0)
                    assertTrue(ui.injectInputEvent(event, true)); event.recycle()
                }
                Thread.sleep(500); aboveKeyboard(); return@runBlocking
            }
            if (scenario == "paste") {
                assertTrue(waitFor { it.text?.toString() == "Zwischenablage vorbelegen" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                assertTrue(field.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            }
            assertTrue(button.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            waitFor { it.text?.contains("· Fertig") == true }
            // Bauleitung injects its known WAV now, after audio.start, via the authorized host.
            Thread.sleep(12_000)
            if (scenario == "field") {
                assertTrue(waitFor { it.hintText?.toString() == "Zweites Textfeld" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                waitFor { it.text?.contains("Einfügen") == true }
                assertTrue(waitFor { it.hintText?.toString() == "Zweites Textfeld" }.text.isNullOrEmpty())
                assertTrue(waitFor { it.text?.toString() == "Zwischenablage prüfen" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                waitFor { !it.isEditable && expected.any { word -> it.text?.contains(word, ignoreCase = true) == true } }
                return@runBlocking
            }
            if (scenario == "rotate") {
                assertTrue(ui.setRotation(UiAutomation.ROTATION_FREEZE_90))
                Thread.sleep(1000)
                // Rotation may end capture if Android replaces the editor; either way no insertion into a new field.
                val outcome = waitFor { it.text?.contains("· Fertig") == true || it.text?.contains("Einfügen") == true }
                if (outcome.text?.contains("Einfügen") == true) {
                    assertTrue(waitFor { it.hintText?.toString() == "Erstes Textfeld" }.text.isNullOrEmpty())
                    assertTrue(waitFor { it.text?.toString() == "Zwischenablage prüfen" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                    waitFor { !it.isEditable && expected.any { word -> it.text?.contains(word, ignoreCase = true) == true } }
                    aboveKeyboard(); return@runBlocking
                }
            }
            val pill = waitFor { it.text?.contains("· Fertig") == true }
            assertTrue(pill.parent.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            if (scenario == "reject") {
                // On API 33+ commitText is acknowledged IPC, not editor acceptance; history remains authoritative.
                waitFor { it.contentDescription?.toString() == "Paply-Diktat starten" }
                assertTrue(waitFor { it.hintText?.toString() == "Editor lehnt Einsetzen ab" }.text.isNullOrEmpty())
                val history = com.paply.android.history.HistoryStore.get(context).entries.value
                assertTrue("Rejected text must be retained", history.any { entry -> entry.id !in previousHistory && expected.any { entry.text.contains(it, ignoreCase = true) } })
                if (android.os.Build.VERSION.SDK_INT < 33) {
                    assertTrue(waitFor { it.text?.toString() == "Zwischenablage prüfen" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                    waitFor { !it.isEditable && expected.any { word -> it.text?.contains(word, ignoreCase = true) == true } }
                }
            } else {
                waitFor { it.isEditable && expected.any { word -> it.text?.contains(word, ignoreCase = true) == true } }
                if (scenario == "paste") {
                    Thread.sleep(800)
                    assertTrue(waitFor { it.text?.toString() == "Zwischenablage prüfen" }.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                    waitFor { it.text?.toString() == "Vorheriger Clip" }
                }
            }
        } finally {
            ui.setRotation(UiAutomation.ROTATION_UNFREEZE)
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, services)
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, enabled)
            prefs.update { previousPrefs }
            ui.dropShellPermissionIdentity()
        }
    } }
}
