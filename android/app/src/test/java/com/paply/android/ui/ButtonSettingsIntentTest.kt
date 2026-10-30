package com.paply.android.ui

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContextWrapper
import android.content.Intent
import android.provider.Settings
import com.paply.android.button.PaplyButtonService
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ButtonSettingsIntentTest {
    private class SettingsContext(private val failures: Int = 0) : ContextWrapper(RuntimeEnvironment.getApplication()) {
        val attempts = mutableListOf<Intent>()
        override fun startActivity(intent: Intent) {
            attempts.add(intent)
            if (attempts.size <= failures) throw ActivityNotFoundException()
        }
    }

    @Test fun accessibilitySettingsHighlightExactlyThePaplyServiceInBothExtras() {
        val context = SettingsContext()
        context.openButtonAccessibilitySettings()
        val intent = context.attempts.single()
        val component = ComponentName(context, PaplyButtonService::class.java).flattenToString()
        assertEquals(Settings.ACTION_ACCESSIBILITY_SETTINGS, intent.action)
        assertEquals(component, intent.getStringExtra(":settings:fragment_args_key"))
        assertEquals(component, intent.getBundleExtra(":settings:show_fragment_args")?.getString(":settings:fragment_args_key"))
    }

    @Test fun unsupportedHighlightRetriesAccessibilitySettingsWithoutExtras() {
        val context = SettingsContext(failures = 1)
        context.openButtonAccessibilitySettings()
        assertEquals(2, context.attempts.size)
        assertEquals(Settings.ACTION_ACCESSIBILITY_SETTINGS, context.attempts.last().action)
        assertNull(context.attempts.last().extras)
    }

    @Test fun missingAccessibilityActivityFallsBackToGeneralSettings() {
        val context = SettingsContext(failures = 2)
        context.openButtonAccessibilitySettings()
        assertEquals(listOf(Settings.ACTION_ACCESSIBILITY_SETTINGS, Settings.ACTION_ACCESSIBILITY_SETTINGS,
            Settings.ACTION_SETTINGS), context.attempts.map { it.action })
        assertNull(context.attempts.last().extras)
    }
}
