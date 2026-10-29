package com.paply.android.ui

import org.junit.Assert.*
import org.junit.Test

class SetupStatusTest {
    @Test fun keyboardTrialSurvivesReturnToPreviousKeyboard() {
        assertFalse(keyboardTried(true, false, false))
        assertTrue(keyboardTried(true, true, false))
        assertTrue(keyboardTried(true, false, true))
        assertTrue(keyboardTried(true, true, true))
    }
    @Test fun disablingKeyboardReopensTrialIncludingAfterReenable() {
        val cleared = keyboardTried(false, false, true)
        assertFalse(cleared)
        assertFalse(keyboardTried(true, false, cleared))
        assertFalse(keyboardTried(false, true, true))
    }
    private val app = "com.paply.android"
    @Test fun oldAndroidAcceptsManualConfirmationEvenWhenTheTileListOmitsPaply() {
        assertTrue(tileAdded("wifi,bt", app, true, 29))
        assertTrue(tileAdded(null, app, true, 32))
        assertFalse(tileAdded("wifi,bt", app, false, 32))
    }
    @Test fun modernAndroidDetectsRemovalFromAReadableList() {
        assertFalse(tileAdded("wifi,bt", app, true, 33))
        assertTrue(tileAdded(null, app, true, 33))
    }
    @Test fun exactTileComponentsAreRecognizedWithoutMatchingOtherPackages() {
        assertTrue(tileAdded("wifi,custom($app/.ThoughtTile)", app, false, 33))
        assertTrue(tileAdded("custom($app/$app.ThoughtTile)", app, false, 33))
        assertFalse(tileAdded("custom(other.$app/.ThoughtTile)", app, false, 33))
    }
}
