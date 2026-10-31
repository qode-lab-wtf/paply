package com.paply.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.paply.android.settings.SettingsRepository
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Exercises the actual settings UI and its persisted developer preferences. */
class DeveloperSettingsDeviceTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun developerPolishSwitchAndHidePersist() = runBlocking {
        val repository = SettingsRepository.get(compose.activity)
        val original = repository.state.value
        repository.update { it.copy(developerMode = true, polish = true) }
        try {
            compose.onNodeWithContentDescription("Einstellungen").performClick()
            compose.onNodeWithText("Entwicklerbereich").performScrollTo().performClick()
            compose.onNodeWithText("Polieren").assertIsDisplayed().performClick()
            compose.waitUntil(5000) { !repository.snapshot().polish }
            assertFalse(repository.snapshot().polish)
            compose.onNodeWithText("Entwicklerbereich ausblenden").performScrollTo().performClick()
            compose.waitUntil(5000) { !repository.state.value.developerMode }
            compose.onNodeWithText("Einstellungen").assertIsDisplayed()
            compose.onNodeWithText("Entwicklerbereich").assertDoesNotExist()
        } finally {
            repository.update { original }
        }
    }
}
