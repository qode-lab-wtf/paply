package com.paply.android.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ButtonSetupTest {
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
