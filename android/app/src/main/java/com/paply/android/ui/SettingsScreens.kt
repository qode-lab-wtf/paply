package com.paply.android.ui

import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.core.net.toUri
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.paply.android.BuildConfig
import com.paply.android.Diag
import com.paply.android.settings.AppPreferences
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.core.GroqClient
import com.paply.core.GroqFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.launch

internal const val PRIVACY = "Dein Ton geht zur Erkennung an Groq, mit deinem Schlüssel – Paply behält davon nur den Text. Gedanken und Verlauf liegen nur auf diesem Gerät. Es wird nichts gespeichert oder gesendet, bis du eine Aufnahme startest."
internal val VERSION = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

@Composable
fun SettingsHome(activity: Activity, prefs: AppPreferences, vault: KeyVault, hasKey: Boolean, keyError: String?,
    status: SetupStatus, keyChanged: () -> Unit, edit: ((AppPreferences) -> AppPreferences) -> Unit,
    navigate: (String) -> Unit, message: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var versionTaps by rememberSaveable { mutableIntStateOf(0) }
    var devHint by rememberSaveable { mutableStateOf<String?>(null) }
    // Deliberately not saveable: neither plaintext draft nor API key enters saved instance state.
    var draft by remember { mutableStateOf("") }
    var keyCheck by rememberSaveable { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }
    var checkFailed by rememberSaveable { mutableStateOf(false) }
    @Suppress("DEPRECATION") // Phase-0-compatible bridge while core is being ported in parallel.
    fun checkKey() {
        if (checking) return
        checking = true
        scope.launch {
            var classification = "failed"
            try {
                val key = withContext(Dispatchers.IO) { vault.read() }
                if (key == null) { keyChanged(); keyCheck = "Bitte zuerst einen Schlüssel sichern."; return@launch }
                withTimeout(15_000) { GroqClient(key).models() }
                classification = "valid"
                keyCheck = "Schlüssel funktioniert"
                checkFailed = false
            } catch (_: TimeoutCancellationException) {
                classification = "offline"
                checkFailed = true
                keyCheck = "Keine Verbindung zu Groq. Der Schlüssel ist gespeichert – prüf ihn, sobald du wieder Netz hast."
            } catch (e: CancellationException) { throw e
            } catch (e: GroqFailure) {
                classification = if (e.status in listOf(401, 403)) "invalid" else if (e.status == 0) "offline" else "failed"
                checkFailed = true
                keyCheck = when (classification) {
                    "invalid" -> "Groq lehnt diesen Schlüssel ab. Bitte neu kopieren und nochmal einsetzen."
                    "offline" -> "Keine Verbindung zu Groq. Der Schlüssel ist gespeichert – prüf ihn, sobald du wieder Netz hast."
                    else -> if (e.status == 429) "Groq-Limit erreicht. Später erneut versuchen." else "Schlüsselprüfung fehlgeschlagen. Bitte später erneut versuchen."
                }
            } catch (_: Exception) {
                checkFailed = true
                keyCheck = "Der Schlüssel konnte nicht gelesen werden. Bitte entfernen und neu sichern."
            } finally {
                checking = false
                Diag.event("settings.apiKey.check valid=${classification == "valid"} invalid=${classification == "invalid"} offline=${classification == "offline"}")
            }
        }
    }
    fun saveKey() {
        if (draft.isBlank() || checking) return
        val value = draft
        checking = true
        scope.launch {
            var saved = false
            try {
                withContext(Dispatchers.IO) { vault.save(value) }
                draft = ""
                keyChanged()
                Diag.event("settings.apiKey present=true")
                saved = true
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { message("Schlüssel konnte nicht sicher gespeichert werden. Bitte erneut versuchen.") }
            finally { checking = false }
            if (saved) checkKey()
        }
    }
    fun removeKey() {
        if (checking) return
        checking = true
        scope.launch {
            try {
                withContext(Dispatchers.IO) { vault.remove() }
                keyCheck = null; checkFailed = false; keyChanged()
                Diag.event("settings.apiKey present=false")
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { message("Schlüssel konnte nicht entfernt werden. Bitte erneut versuchen.") }
            finally { checking = false }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Section("Groq-Schlüssel", "Der Schlüssel bleibt nur auf diesem Gerät. Gilt für Diktat und Gedanken.") {
            if (hasKey) {
                SettingsItem("Schlüssel gespeichert", icon = PaplyIcons.KeyRound, value = "Verschlüsselt auf diesem Gerät")
                Hairline()
                TextButton(onClick = { checkKey() }, enabled = !checking, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Schlüssel prüfen") }
                TextButton(onClick = { removeKey() }, enabled = !checking, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Schlüssel entfernen", color = C.danger) }
            } else {
                SettingsItem("Kostenlosen Schlüssel holen", icon = PaplyIcons.KeyRound, onClick = {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, "https://console.groq.com/keys".toUri()))
                })
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    listOf("Bei Groq kostenlos anmelden", "„Create API Key“ tippen und kopieren", "Hier „Einsetzen“").forEachIndexed { index, text ->
                        Text("${index + 1}   $text", color = C.text.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
                    }
                    OutlinedTextField(value = draft, onValueChange = { draft = it }, label = { Text("gsk_…") },
                        visualTransformation = PasswordVisualTransformation(), singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                        modifier = Modifier.fillMaxWidth())
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        TextButton(onClick = {
                            val clipboard = activity.getSystemService(ClipboardManager::class.java)
                            val pasted = clipboard.primaryClip?.getItemAt(0)?.coerceToText(activity)?.toString()
                            if (!pasted.isNullOrBlank()) {
                                draft = pasted
                                clipboard.clearPrimaryClip()
                                saveKey()
                            } else message("Die Zwischenablage ist leer.")
                        }, enabled = !checking) { Text("Einsetzen") }
                        TextButton(onClick = { saveKey() }, enabled = draft.isNotBlank() && !checking) { Text("Sichern") }
                    }
                }
            }
            val keyStatus = keyError ?: if (checking) "Prüfe …" else keyCheck
            if (keyStatus != null) Text(keyStatus, style = MaterialTheme.typography.bodyMedium,
                color = if (keyError != null || checkFailed) C.beak else C.greenBright,
                modifier = Modifier.padding(16.dp))
            if (keyError != null && !hasKey) TextButton(onClick = { removeKey() }, enabled = !checking,
                modifier = Modifier.padding(horizontal = 8.dp)) { Text("Schlüssel entfernen", color = C.danger) }
        }
        Section("Erkennung", if (prefs.betaThoughts) "Gilt für Diktat und Gedanken." else "Gilt fürs Diktat.") {
            SettingsItem("Sprachen", icon = PaplyIcons.Globe,
                value = (if (prefs.automaticLanguages) "Automatisch" else "Eigene") + " (${prefs.languages.take(3).joinToString(", ", transform = SettingsRepository::languageName)})",
                onClick = { navigate("languages") })
            Hairline()
            val count = prefs.vocabulary.split(',', '\n').count { it.isNotBlank() }
            SettingsItem("Eigene Begriffe", icon = PaplyIcons.BookA, value = if (count == 0) "keine" else "$count", onClick = { navigate("vocabulary") })
        }
        Section("Beta", "Neue Funktionen im Test: Gedanken per Knopf festhalten und Aufgaben. Aus heißt nur ausgeblendet – deine Gedanken und Aufgaben bleiben gespeichert.") {
            SettingsToggle("Gedanken & Aufgaben", prefs.betaThoughts,
                { on -> edit { it.copy(betaThoughts = on) } }, icon = PaplyIcons.FlaskConical)
        }
        if (prefs.betaThoughts) Section("Gedanken", "Aufnahmen werden nach der Umschrift sofort gelöscht, Text und Aufgaben bleiben. Gesendet wird nur an Groq, mit deinem Schlüssel.") {
            SettingsItem("Gedanken-Knopf einrichten", icon = PaplyIcons.Lightbulb, value = if (status.tileAdded) "eingerichtet" else "fehlt noch", onClick = { navigate("tile") })
        }
        Section {
            SettingsItem("Tastatur einrichten", icon = PaplyIcons.Keyboard,
                value = if (status.keyboardSelected) "Paply ist ausgewählt" else if (status.keyboardEnabled) "aktiviert · noch nicht ausgewählt" else "fehlt noch",
                onClick = { navigate("keyboard") })
            if (prefs.developerMode) {
                Hairline()
                SettingsItem("Entwicklerbereich", icon = PaplyIcons.Hammer, onClick = { navigate("developer") })
            }
        }
        Section("Datenschutz") { Text(PRIVACY, style = MaterialTheme.typography.bodyMedium, color = C.secondary, modifier = Modifier.padding(16.dp)) }
        Section(footer = "Mit App- und Android-Version sowie den letzten 200 Diagnose-Ereignissen seit dem App-Start: nur Abläufe, Zahlen und Ja/Nein-Werte, keine Inhalte oder Kennungen.") {
            SettingsItem("Feedback senden", icon = PaplyIcons.MessageSquare, onClick = {
                scope.launch { shareText(activity, "Feedback zu Paply $VERSION, Android ${Build.VERSION.RELEASE}:\n\n" + DiagnosticReader.read(), "Paply-Feedback") }
            })
        }
        Section(footer = devHint) {
            SettingsItem("Version", value = VERSION, onClick = {
                versionTaps++
                if (prefs.developerMode || versionTaps >= 5) {
                    edit { it.copy(developerMode = true) }
                    devHint = "Entwicklerbereich ist an."
                    navigate("developer")
                } else if (versionTaps >= 3) devHint = "Noch ${5 - versionTaps}× tippen …"
            })
        }
    }
}

@Composable
fun LanguagesScreen(prefs: AppPreferences, edit: ((AppPreferences) -> AppPreferences) -> Unit) {
    var primary by rememberSaveable { mutableStateOf(false) }
    val deviceLanguage = LocalConfiguration.current.locales[0].language
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Section(footer = if (prefs.automaticLanguages) "Erkannt: ${prefs.detectedLanguages.joinToString(", ", transform = SettingsRepository::languageName)}. Aus deinen Tastaturen und den Gerätesprachen; ist es nur eine, kommt Englisch dazu."
            else "Wähle die Sprachen, die du sprichst – auch gemischt in einem Satz.") {
            SettingsToggle("Automatisch", prefs.automaticLanguages, { on -> edit { it.copy(automaticLanguages = on,
                manualLanguages = if (!on && it.manualLanguages.isEmpty()) it.detectedLanguages else it.manualLanguages) } },
                description = "Sprachen automatisch")
        }
        if (!prefs.automaticLanguages) Section("Deine Sprachen") {
            (SettingsRepository.commonLanguages + prefs.detectedLanguages + prefs.manualLanguages).distinct().forEach { code ->
                SettingsItem(SettingsRepository.languageName(code), onClick = { edit { current ->
                    current.copy(manualLanguages = if (code in current.manualLanguages) current.manualLanguages - code else current.manualLanguages + code)
                } }, trailing = {
                    if (code in prefs.manualLanguages) Glyph(PaplyIcons.Check, "Ausgewählt", C.greenBright)
                })
            }
        }
        Section(footer = "Kurze Sätze schreibt Paply direkt in der Hauptsprache, statt die Sprache zu raten.") {
            SettingsItem("Hauptsprache", value = SettingsRepository.languageName(prefs.dictationPrefs().mainLanguage), onClick = { primary = true })
        }
        Text("Bei längeren Sätzen erkennt Paply die Sprache selbst. Die Liste hilft, wenn du mitten im Satz wechselst – zum Beispiel ein englischer Satz in einer deutschen Nachricht. Erkennt Paply eine Sprache, die nicht in der Liste steht, schreibt es in der Hauptsprache.",
            color = C.secondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp))
    }
    if (primary) AlertDialog(onDismissRequest = { primary = false }, title = { Text("Hauptsprache") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            prefs.languages.ifEmpty { listOf(deviceLanguage) }.distinct().forEach { code ->
                SettingsItem(SettingsRepository.languageName(code), onClick = { edit { it.copy(mainLanguage = code) }; primary = false }, trailing = {
                    if (code == prefs.dictationPrefs().mainLanguage) Glyph(PaplyIcons.Check, "Ausgewählt", C.greenBright)
                })
            }
        } }, confirmButton = { TextButton(onClick = { primary = false }) { Text("Fertig") } })
}

@Composable
fun VocabularyScreen(prefs: AppPreferences, edit: ((AppPreferences) -> AppPreferences) -> Unit) {
    var draft by rememberSaveable { mutableStateOf(prefs.vocabulary) }
    val latestEdit by rememberUpdatedState(edit)
    val savedVocabulary by rememberUpdatedState(prefs.vocabulary)
    LaunchedEffect(draft) {
        delay(500)
        val value = draft
        if (value != savedVocabulary) latestEdit { it.copy(vocabulary = value) }
    }
    DisposableEffect(Unit) {
        onDispose {
            val value = draft
            if (value != savedVocabulary) latestEdit { it.copy(vocabulary = value) }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedTextField(value = draft, onValueChange = { text -> draft = text },
            label = { Text("Eigene Begriffe") }, minLines = 9,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false), modifier = Modifier.fillMaxWidth())
        Text("Namen und Fachwörter, getrennt durch Komma oder neue Zeile. Paply schreibt sie dann richtig.",
            style = MaterialTheme.typography.bodySmall, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp))
    }
}

@Composable
fun DeveloperScreen(prefs: AppPreferences, edit: ((AppPreferences) -> AppPreferences) -> Unit, navigate: (String) -> Unit) {
    var models by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Section("Diktat") {
            SettingsItem("Transkription", value = if (prefs.transcriptionModel.endsWith("turbo")) "large-v3-turbo (schneller)" else "large-v3 (genauer)", onClick = { models = true })
            Hairline()
            SettingsToggle("Stücke-Upload", prefs.chunkUpload, { on -> edit { it.copy(chunkUpload = on) } })
        }
        Section("Werkzeuge") { SettingsItem("Diagnose", icon = PaplyIcons.AudioLines, onClick = { navigate("diagnostics") }) }
    }
    if (models) AlertDialog(onDismissRequest = { models = false }, title = { Text("Transkription") }, text = {
        Column {
            listOf("whisper-large-v3" to "large-v3 (genauer)", "whisper-large-v3-turbo" to "large-v3-turbo (schneller)").forEach { (id, label) ->
                SettingsItem(label, onClick = { edit { it.copy(transcriptionModel = id) }; models = false }, trailing = {
                    if (id == prefs.transcriptionModel) Glyph(PaplyIcons.Check, "Ausgewählt", C.greenBright)
                })
            }
        }
    }, confirmButton = { TextButton(onClick = { models = false }) { Text("Fertig") } })
}
