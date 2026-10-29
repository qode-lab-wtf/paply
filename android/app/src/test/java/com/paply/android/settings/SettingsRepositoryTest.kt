package com.paply.android.settings

import androidx.datastore.core.CorruptionException
import androidx.datastore.core.DataStoreFactory
import java.io.ByteArrayInputStream
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SettingsRepositoryTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun paplyButtonDefaultsOnForNewAndPreviouslyUnsetPreferences() {
        assertTrue(AppPreferences().paplyButton)
        assertTrue(SettingsRepository.decode("{}").paplyButton)
    }

    @Test fun explicitPaplyButtonChoiceSurvivesRoundTrip() {
        listOf(false, true).forEach { enabled ->
            val prefs = SettingsRepository.decode("""{"paplyButton":$enabled}""")
            assertEquals(enabled, prefs.paplyButton)
            assertEquals(enabled, SettingsRepository.decode(SettingsRepository.encode(prefs)).paplyButton)
        }
    }

    @Test fun languageCodesAreIsoAndLegacyAliasesBecomeModernCodes() {
        assertEquals(listOf("he", "id", "yi", "de", "zh"), LanguageCodes.list(
            listOf("iw-IL", "he", "in_ID", "ji", "de-DE", "zh-Hant", "zz", "xyz", "mul", "und", "zxx", "emoji", "en-XA", "ar_XB")))
    }
    @Test fun detectionUsesIosKeyboardThenDeviceOrderAndDeduplicates() {
        assertEquals(listOf("tr", "de", "fr", "en"), LanguageCodes.detected(listOf("tr-TR", "de-DE"), listOf("fr-FR", "de", "en-US")))
    }
    @Test fun auxiliaryAndNonKeyboardSubtypesAreIgnored() {
        assertNull(LanguageCodes.keyboard("keyboard", true, "fr-FR"))
        assertNull(LanguageCodes.keyboard("voice", false, "de-DE"))
        assertNull(LanguageCodes.keyboard("keyboard", false, "zz"))
        assertEquals("he", LanguageCodes.keyboard("keyboard", false, "iw-IL"))
    }
    @Test fun singleNonEnglishLanguageAddsEnglishAndEmptyDetectionFallsBackToEnglish() {
        assertEquals(listOf("de", "en"), LanguageCodes.detected(listOf("de"), listOf("de-DE")))
        assertEquals(listOf("en"), LanguageCodes.detected(emptyList(), listOf("zz")))
        assertEquals(listOf("en"), LanguageCodes.detected(listOf("en"), emptyList()))
    }
    @Test fun savedLanguagesAreNormalizedToo() {
        val prefs = SettingsRepository.decode("""{"detectedLanguages":["iw","zz"],"manualLanguages":["in","id","emoji"],"mainLanguage":"ji"}""")
        assertEquals(listOf("he"), prefs.detectedLanguages)
        assertEquals(listOf("id"), prefs.manualLanguages)
        assertEquals("yi", prefs.mainLanguage)
    }
    @Test fun malformedJsonIsReportedAsDataStoreCorruption() = runBlocking {
        try { SettingsSerializer(AppPreferences()).readFrom(ByteArrayInputStream("{".toByteArray())); fail() }
        catch (e: CorruptionException) { assertTrue(e.cause is org.json.JSONException) }
    }
    @Test fun corruptedDataStoreIsArchivedAndAcceptsFurtherEdits() = runBlocking {
        val file = File(temporary.root, "paply-settings.json").apply { writeText("broken-json") }
        val defaults = AppPreferences(detectedLanguages = listOf("de", "en"))
        val job = SupervisorJob()
        val store = DataStoreFactory.create(serializer = SettingsSerializer(defaults),
            corruptionHandler = settingsCorruptionHandler(file, defaults),
            scope = CoroutineScope(job + Dispatchers.IO), produceFile = { file })
        try {
            assertEquals(defaults, withTimeout(10_000) { store.data.first() })
            val archive = temporary.root.listFiles()!!.single { it.name.startsWith("damaged-") }
            assertEquals("broken-json", archive.readText())
            store.updateData { it.copy(vocabulary = "Paply") }
            assertEquals("Paply", SettingsRepository.decode(file.readText()).vocabulary)
        } finally { job.cancelAndJoin() }
    }
}
