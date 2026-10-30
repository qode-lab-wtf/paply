package com.paply.android.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ButtonSetupTest {
    private fun transition(stage: ButtonSetupStage, event: ButtonSetupEvent, enabled: Boolean = false,
        restricted: Boolean = true) = nextButtonSetupStage(stage, event, enabled, restricted)

    @Test fun restrictedSettingsCycleReturnsToFirstStepAfterAppInfoAndCanRepeat() {
        var stage = ButtonSetupStage.START
        repeat(2) {
            stage = transition(stage, ButtonSetupEvent.OPEN_ACCESSIBILITY)
            assertEquals(ButtonSetupStage.ACCESSIBILITY_OPEN, stage)
            stage = transition(stage, ButtonSetupEvent.RESUME)
            assertEquals(ButtonSetupStage.APP_INFO, stage)
            stage = transition(stage, ButtonSetupEvent.OPEN_APP_INFO)
            assertEquals(ButtonSetupStage.APP_INFO_OPEN, stage)
            stage = transition(stage, ButtonSetupEvent.RESUME)
            assertEquals(ButtonSetupStage.RETRY_ACCESSIBILITY, stage)
            // An unrelated resume must not undo the retry instruction.
            stage = transition(stage, ButtonSetupEvent.RESUME)
            assertEquals(ButtonSetupStage.RETRY_ACCESSIBILITY, stage)
        }
    }

    @Test fun successfulActivationClearsEverySetupStage() {
        ButtonSetupStage.entries.forEach { stage ->
            assertEquals(ButtonSetupStage.START, transition(stage, ButtonSetupEvent.RESUME, enabled = true))
        }
    }

    @Test fun resumeWithoutOpeningSettingsKeepsFirstStepAndAppInfoHighlight() {
        assertEquals(ButtonSetupStage.START, transition(ButtonSetupStage.START, ButtonSetupEvent.RESUME))
        assertEquals(ButtonSetupStage.APP_INFO, transition(ButtonSetupStage.APP_INFO, ButtonSetupEvent.RESUME))
    }

    @Test fun olderAndroidReturnsToFirstStepWithoutRestrictedSettings() {
        val stage = transition(ButtonSetupStage.START, ButtonSetupEvent.OPEN_ACCESSIBILITY, restricted = false)
        assertEquals(ButtonSetupStage.START, transition(stage, ButtonSetupEvent.RESUME, restricted = false))
    }

    @Test fun appInfoCanBeOpenedBeforeFirstAccessibilityAttempt() {
        val stage = transition(ButtonSetupStage.START, ButtonSetupEvent.OPEN_APP_INFO)
        assertEquals(ButtonSetupStage.RETRY_ACCESSIBILITY, transition(stage, ButtonSetupEvent.RESUME))
    }

    @Test fun samsungUsesInstalledAppsIncludingMixedCaseManufacturer() {
        val expected = "Dort: Installierte Apps → Paply → einschalten."
        assertEquals(expected, buttonSetupLocation("samsung"))
        assertEquals(expected, buttonSetupLocation("SAMSUNG"))
        assertEquals(expected, buttonSetupLocation("Samsung"))
    }

    @Test fun otherManufacturersIncludeBothPossibleAppLists() {
        val expected = "Dort: Heruntergeladene Apps (oder Installierte Apps) → Paply → einschalten."
        listOf("Google", "Xiaomi", "", "other").forEach {
            assertEquals(expected, buttonSetupLocation(it))
        }
    }
}
