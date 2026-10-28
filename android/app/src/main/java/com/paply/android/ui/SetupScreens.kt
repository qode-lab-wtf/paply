package com.paply.android.ui

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import com.paply.android.settings.AppPreferences
import com.paply.android.settings.SettingsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun SetupCard(prefs: AppPreferences, status: SetupStatus, hasKey: Boolean, microphone: () -> Unit,
    notifications: () -> Unit, navigate: (String) -> Unit,
) {
    data class Step(val title: String, val detail: String, val done: Boolean, val action: String, val click: () -> Unit,
        val confirmTile: Boolean = false)
    val steps = buildList {
        add(Step("Mikro erlauben", if (prefs.betaThoughts) "Für Diktat und Gedanken." else "Fürs Diktat.", status.microphone, "Erlauben", microphone))
        add(Step("Benachrichtigungen erlauben", "Damit du laufende Aufnahmen immer siehst.", status.notifications, "Erlauben", notifications))
        add(Step("Groq-Schlüssel", "Kostenlos bei Groq, in einer Minute erledigt.", hasKey, "Eintragen", { navigate("settings") }))
        add(Step("Tastatur aktivieren", "Paply in den Android-Tastatureinstellungen einschalten.", status.keyboardEnabled, "Einrichten", { navigate("keyboard") }))
        add(Step("Tastatur auswählen", "Paply als aktuelle Tastatur auswählen.", status.keyboardSelected, "Auswählen", { navigate("keyboard") }))
        if (prefs.betaThoughts) add(Step("Gedanken-Kachel hinzufügen", "In den Schnelleinstellungen – ein Tipp, und du sprichst.", status.tileAdded, "Einrichten", { navigate("tile") }, confirmTile = true))
    }
    val expandedType = LocalDensity.current.fontScale >= 1.5f
    val done = steps.count { it.done }
    if (done == steps.size) return
    PaplyCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Einrichten", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            Text("$done von ${steps.size}", style = MaterialTheme.typography.bodyMedium, color = C.secondary)
        }
        val next = steps.indexOfFirst { !it.done }
        steps.forEachIndexed { index, step ->
            Column(Modifier.fillMaxWidth().padding(vertical = 9.dp).semantics { stateDescription = if (step.done) "erledigt" else "offen" }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Glyph(if (step.done) PaplyIcons.Check else PaplyIcons.Circle, tint = if (step.done) C.greenBright else C.tertiary, size = 24.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(step.title, style = MaterialTheme.typography.bodyLarge, color = if (step.done) C.secondary else C.text)
                        if (index == next) Text(step.detail, style = MaterialTheme.typography.bodySmall, color = C.secondary)
                    }
                    if (!step.done && !expandedType) Pill(step.action, step.click, prominent = index == next)
                }
                if (!step.done && expandedType) Box(Modifier.fillMaxWidth().padding(start = 36.dp), contentAlignment = Alignment.CenterEnd) {
                    Pill(step.action, step.click, prominent = index == next)
                }
                if (!step.done && step.confirmTile && Build.VERSION.SDK_INT < 33) LegacyTileConfirmation()
            }
            if (index != steps.lastIndex) Hairline()
        }
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Glyph(PaplyIcons.ShieldCheck, tint = C.thoughtMint, size = 16.dp)
            Text(if (prefs.betaThoughts) PRIVACY else PRIVACY.replace("Gedanken und Verlauf liegen", "Der Verlauf liegt"),
                color = C.secondary, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
fun KeyboardSetupScreen(activity: Activity, status: SetupStatus) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("Die Tastatur merkt sich nichts, was du tippst. Nur deine Sprachaufnahme wird mit deinem Schlüssel an Groq gesendet.", color = C.secondary, style = MaterialTheme.typography.bodyMedium)
        PaplyCard {
            StatusLine("Paply als Tastatur aktiviert", status.keyboardEnabled)
            StatusLine("Paply als Tastatur ausgewählt", status.keyboardSelected)
        }
        GuideCard("So geht’s", listOf("„Einstellungen öffnen“ tippen.", "„Paply“ in der Tastaturliste einschalten.",
            "Zurück zu Paply und „Tastatur auswählen“ tippen.", "In einem Textfeld Paply auswählen und sprechen."))
        GuideCard("Aus Gboard zu Paply", listOf(
            "Öffne ein Textfeld. Tippe auf den System-Tastaturwechsler unten rechts, außerhalb der Gboard-Tasten.",
            "Bei mehreren Gboard-Sprachen kann zuerst die nächste Sprache erscheinen. Tippe dann nochmals. Du kannst die Taste auch halten und Paply direkt auswählen.",
            "Sobald das grüne Paply-Panel erscheint, sprich. Tippen beendet das Diktat; danach geht es zurück zur vorherigen Tastatur."))
        Text("Android bestimmt die Reihenfolge. Mit einer Gboard-Sprache reicht auf neueren Pixel-Systemen meist ein Tipp; bei älteren Systemen öffnet sich eine Auswahl. Deine Gboard-Sprachen bleiben erhalten. Paply erkennt die gesprochene Sprache unabhängig davon.",
            color = C.secondary, style = MaterialTheme.typography.bodySmall)
        Pill("Einstellungen öffnen", { activity.openKeyboardSettings() })
        Pill("Tastatur auswählen", { activity.chooseKeyboard() }, prominent = false)
    }
}

@Composable
fun TileSetupScreen(activity: Activity, status: SetupStatus, addTile: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("Ein Tipp, und du sprichst. Der Gedanken-Knopf startet die Aufnahme direkt aus den Schnelleinstellungen.", color = C.secondary, style = MaterialTheme.typography.bodyMedium)
        PaplyCard { StatusLine("Gedanken-Kachel hinzugefügt", status.tileAdded) }
        GuideCard("So geht’s", if (Build.VERSION.SDK_INT >= 33) listOf("„Kachel hinzufügen“ tippen.", "Im Android-Dialog „Hinzufügen“ wählen.",
            "Vom oberen Bildschirmrand zweimal nach unten wischen und „Paply-Gedanke“ tippen.")
            else listOf("Vom oberen Bildschirmrand zweimal nach unten wischen.", "Die Schnelleinstellungen bearbeiten (Stift-Symbol).",
                "„Paply-Gedanke“ zu deinen Kacheln ziehen.", "Zum Aufnehmen die Kachel antippen."))
        if (Build.VERSION.SDK_INT >= 33) Pill("Kachel hinzufügen", addTile)
        else if (!status.tileAdded) LegacyTileConfirmation()
        Text("Aufnahmen werden nach der Umschrift sofort gelöscht, Text und Aufgaben bleiben. Gesendet wird nur an Groq, mit deinem Schlüssel.", style = MaterialTheme.typography.bodySmall, color = C.secondary)
    }
}

@Composable
private fun LegacyTileConfirmation() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Kachel schon hinzugefügt? Manche Android-Versionen können das nicht erkennen. Bestätige es hier.",
            style = MaterialTheme.typography.bodySmall, color = C.secondary)
        Pill(if (saving) "Sichere …" else "Erledigt", {
            if (!saving) {
                saving = true
                scope.launch {
                    try { SettingsRepository.get(context).update { it.copy(tileAdded = true) }; error = false }
                    catch (e: CancellationException) { throw e }
                    catch (_: Exception) { error = true }
                    finally { saving = false }
                }
            }
        }, prominent = false, enabled = !saving)
        if (error) Text("Bitte erneut versuchen.", color = C.danger, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun GuideCard(title: String, steps: List<String>) {
    PaplyCard {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        steps.forEachIndexed { index, text ->
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${index + 1}", color = C.thoughtMint, style = MaterialTheme.typography.titleSmall)
                Text(text, style = MaterialTheme.typography.bodyMedium, color = C.text.copy(alpha = 0.85f))
            }
        }
    }
}
