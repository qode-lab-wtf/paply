package com.paply.android.ui

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class LanguageHelpTest {
    @Test fun helpExplainsDetectionWithoutTranslation() {
        val source = File("src/main/java/com/paply/android/ui/SettingsScreens.kt").readText()
        assertTrue(source.contains("Paply übersetzt nie. Die Hauptsprache gilt nur, wenn die Erkennung unsicher ist."))
        assertFalse(source.contains("Kurze Sätze schreibt Paply direkt"))
        assertFalse(source.contains("schreibt es in der Hauptsprache"))
    }
}
