package com.paply.android.ui

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import com.paply.android.ui.theme.PaplyColors as C
import androidx.compose.ui.platform.LocalContext
import androidx.core.net.toUri
import com.paply.android.settings.*
import com.paply.android.ui.components.*
import kotlinx.coroutines.launch

@Composable
fun ButtonSetupCard(prefs: AppPreferences) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var triedAccessibility by rememberSaveable { mutableStateOf(false) }
    var returnedWithoutService by remember { mutableStateOf(false) }
    val enabled = rememberButtonServiceEnabled { isEnabled ->
        returnedWithoutService = triedAccessibility && !isEnabled
    }
    val highlightAppInfo = Build.VERSION.SDK_INT >= 33 && returnedWithoutService
    var error by remember { mutableStateOf(false) }
    PaplyCard {
        Text("Paply-Knopf neben der Tastatur")
        Text("Paply erkennt aktive Schreibfelder, Passwortfelder und die Lage der Tastatur. Inhalte anderer Apps werden nicht gelesen, gespeichert oder protokolliert. Nur dein Tipp startet die Aufnahme.")
        SettingsToggle("Paply-Knopf neben der Tastatur", prefs.paplyButton, { on ->
            scope.launch {
                try { SettingsRepository.get(context).update { it.copy(paplyButton = on) }; error = false }
                catch (e: kotlinx.coroutines.CancellationException) { throw e }
                catch (_: Exception) { error = true }
            }
        })
        if (error) Text("Einstellung konnte nicht gespeichert werden. Bitte erneut versuchen.")
        StatusLine("Bedienungshilfe eingeschaltet", enabled)
        if (enabled && prefs.paplyButton) {
            Text("Unten rechts erscheint ein Bedienungshilfe-Symbol? In den Einstellungen bei Paply-Knopf die „Verknüpfung“ ausschalten.",
                style = MaterialTheme.typography.bodySmall, color = C.secondary)
            Text("Fertig. Tipp in ein Textfeld – der Paply-Knopf erscheint über deiner Tastatur.")
        } else if (prefs.paplyButton) {
            Text("Schritt 1", style = MaterialTheme.typography.titleSmall)
            Pill("Bedienungshilfe öffnen", {
                triedAccessibility = true
                context.openButtonAccessibilitySettings()
            }, prominent = !highlightAppInfo)
            Text(buttonSetupLocation(Build.MANUFACTURER), style = MaterialTheme.typography.bodyMedium, color = C.secondary)
            if (Build.VERSION.SDK_INT >= 33) {
                Text("Schritt 2", style = MaterialTheme.typography.titleSmall, color = if (highlightAppInfo) C.text else C.secondary)
                Text("Zeigt Android „Eingeschränkte Einstellung“? Dann: App-Info öffnen → ⋮ oben rechts → „Eingeschränkte Einstellungen zulassen“ → danach Schritt 1 noch einmal.",
                    style = MaterialTheme.typography.bodyMedium, color = if (highlightAppInfo) C.text else C.secondary)
                Pill("App-Info öffnen", {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri()))
                }, prominent = highlightAppInfo)
            }
        }
    }
}
