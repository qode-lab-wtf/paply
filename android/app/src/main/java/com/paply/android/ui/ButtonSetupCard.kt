package com.paply.android.ui

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.paply.android.ui.theme.PaplyColors as C
import androidx.core.net.toUri
import com.paply.android.settings.*
import com.paply.android.ui.components.*
import kotlinx.coroutines.launch

@Composable
fun ButtonSetupCard(prefs: AppPreferences) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var stage by rememberSaveable { mutableStateOf(ButtonSetupStage.START) }
    val restrictedSettingsPossible = Build.VERSION.SDK_INT >= 33
    val enabled = rememberButtonServiceEnabled { isEnabled ->
        stage = nextButtonSetupStage(stage, ButtonSetupEvent.RESUME, isEnabled, restrictedSettingsPossible)
    }
    val highlightAppInfo = restrictedSettingsPossible && stage == ButtonSetupStage.APP_INFO
    var error by remember { mutableStateOf(false) }
    PaplyCard {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Paply-Knopf", style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() })
            Text("Paply erkennt aktive Schreibfelder, Passwortfelder und die Lage der Tastatur. Inhalte anderer Apps werden nicht gelesen, gespeichert oder protokolliert. Nur dein Tipp startet die Aufnahme.",
                style = MaterialTheme.typography.bodyMedium, color = C.secondary)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SettingsToggle("Knopf über der Tastatur anzeigen", prefs.paplyButton, { on ->
                    scope.launch {
                        try { SettingsRepository.get(context).update { it.copy(paplyButton = on) }; error = false }
                        catch (e: kotlinx.coroutines.CancellationException) { throw e }
                        catch (_: Exception) { error = true }
                    }
                })
                if (error) Text("Einstellung konnte nicht gespeichert werden. Bitte erneut versuchen.")
                StatusLine("Bedienungshilfe eingeschaltet", enabled)
            }
            if (enabled && prefs.paplyButton) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Fertig. Tipp in ein Textfeld – der Paply-Knopf erscheint über dem Eingabefeld.")
                    Text("Unten rechts erscheint ein Bedienungshilfe-Symbol? In den Einstellungen bei Paply-Knopf die „Verknüpfung“ ausschalten.",
                        style = MaterialTheme.typography.bodySmall, color = C.secondary)
                }
            } else if (prefs.paplyButton) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Schritt 1", style = MaterialTheme.typography.titleSmall)
                    if (stage == ButtonSetupStage.RETRY_ACCESSIBILITY) {
                        Text("Jetzt Paply noch einmal einschalten.", style = MaterialTheme.typography.bodyMedium, color = C.secondary)
                    }
                    Pill("Bedienungshilfe öffnen", {
                        stage = nextButtonSetupStage(stage, ButtonSetupEvent.OPEN_ACCESSIBILITY, enabled, restrictedSettingsPossible)
                        context.openButtonAccessibilitySettings()
                    }, prominent = !highlightAppInfo)
                    Text(buttonSetupLocation(Build.MANUFACTURER), style = MaterialTheme.typography.bodyMedium, color = C.secondary)
                }
                if (restrictedSettingsPossible) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Schritt 2", style = MaterialTheme.typography.titleSmall, color = if (highlightAppInfo) C.text else C.secondary)
                        Text("Zeigt Android „Eingeschränkte Einstellung“? Dann: App-Info öffnen → ⋮ oben rechts → „Eingeschränkte Einstellungen zulassen“ → danach Schritt 1 noch einmal.",
                            style = MaterialTheme.typography.bodyMedium, color = if (highlightAppInfo) C.text else C.secondary)
                        Pill("App-Info öffnen", {
                            stage = nextButtonSetupStage(stage, ButtonSetupEvent.OPEN_APP_INFO, enabled, restrictedSettingsPossible)
                            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri()))
                        }, prominent = highlightAppInfo)
                    }
                }
            }
        }
    }
}
