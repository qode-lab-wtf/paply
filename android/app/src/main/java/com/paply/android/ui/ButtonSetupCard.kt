package com.paply.android.ui

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import androidx.compose.runtime.*
import androidx.compose.material3.Text
import androidx.compose.ui.platform.LocalContext
import androidx.core.net.toUri
import com.paply.android.button.PaplyButtonService
import com.paply.android.settings.*
import com.paply.android.ui.components.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun ButtonSetupCard(prefs: AppPreferences) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var enabled by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            enabled = context.getSystemService(AccessibilityManager::class.java)
                .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .any { ComponentName.unflattenFromString(it.id) == ComponentName(context, PaplyButtonService::class.java) }
            delay(500)
        }
    }
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
        if (prefs.paplyButton) {
            if (Build.VERSION.SDK_INT >= 33) {
                Text("1. Falls Android die Freigabe sperrt: App-Info → ⋮ → Eingeschränkte Einstellungen zulassen.")
                Pill("App-Info öffnen", { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())) }, prominent = false)
            }
            Text("${if (Build.VERSION.SDK_INT >= 33) "2. " else ""}Unter Bedienungshilfen den Paply-Knopf einschalten. Danach ein Schreibfeld öffnen und auf Paply tippen.")
            Pill("Bedienungshilfe öffnen", { context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) })
        }
    }
}
