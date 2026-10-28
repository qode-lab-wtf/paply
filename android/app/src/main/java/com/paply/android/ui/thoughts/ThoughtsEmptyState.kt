package com.paply.android.ui.thoughts

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C

@Composable
fun ThoughtsEmptyState(setup: @Composable () -> Unit, onGuide: () -> Unit, onCapture: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        AndroidThoughtIllustration()
        Text("Deine Gedanken", style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 16.dp).semantics { heading() })
        Text("Drück die Paply-Kachel in den Schnelleinstellungen und sprich – wie in ein Diktiergerät. Paply räumt auf, findet das Thema und merkt sich Aufgaben.",
            style = MaterialTheme.typography.bodyLarge, color = C.secondary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Button(onClick = onCapture, modifier = Modifier.widthIn(max = 300.dp).fillMaxWidth().heightIn(min = 52.dp), shape = CircleShape) {
            Text("Hier ausprobieren", style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = onGuide) { Text("Knopf einrichten", style = MaterialTheme.typography.titleMedium) }
        setup()
    }
}

@Composable
private fun AndroidThoughtIllustration() {
    Column(Modifier.width(152.dp).height(216.dp).clip(RoundedCornerShape(28.dp)).background(C.forest)
        .border(1.dp, C.secondary.copy(alpha=.3f), RoundedCornerShape(28.dp)).padding(16.dp)
        .semantics(mergeDescendants = true) { contentDescription = "Android-Schnelleinstellungen mit Paply-Gedanke-Kachel" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(6.dp).background(C.tertiary, CircleShape))
        Text("9:41", fontSize = 30.sp, color = C.text)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(50.dp, 30.dp).background(C.row, CircleShape))
            Box(Modifier.size(50.dp, 30.dp).background(C.row, CircleShape))
        }
        Row(Modifier.fillMaxWidth().background(C.greenBright, RoundedCornerShape(20.dp)).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaplyMark(Modifier.size(16.dp, 18.dp), C.forest)
            Text("Paply", color = C.forest, style = MaterialTheme.typography.labelMedium)
        }
        Box(Modifier.fillMaxWidth().height(16.dp).background(C.row, RoundedCornerShape(4.dp)))
    }
}

@Composable
fun ThoughtButtonGuide(onBack: () -> Unit, onTileSetup: () -> Unit, onCapture: () -> Unit) {
    ThoughtToolbar("Gedanken-Knopf", onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        AndroidThoughtIllustration()
        Text("Ein Druck nimmt einen Gedanken auf, nochmal drücken beendet. Paply ordnet ihn danach in der App.", color = C.secondary, style = MaterialTheme.typography.bodyLarge)
        PaplyCard {
            Text("Schnelleinstellungen", style = MaterialTheme.typography.titleLarge)
            listOf("Vom oberen Bildschirmrand zweimal nach unten wischen.", "Die Schnelleinstellungen bearbeiten (Stift-Symbol).",
                "„Paply-Gedanke“ zu deinen Kacheln ziehen.", "Zum Aufnehmen die Kachel antippen. Nochmal tippen oder „Fertig“ beendet.").forEachIndexed { i, line ->
                Text("${i+1}. $line", modifier = Modifier.padding(top = 10.dp), style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.height(12.dp)); Pill("Kachel hinzufügen", onTileSetup)
        }
        PaplyCard {
            Text("Auf dem Home-Bildschirm", style = MaterialTheme.typography.titleLarge)
            listOf("Auf eine freie Stelle des Home-Bildschirms lange drücken.", "„Widgets“ öffnen und „Paply“ suchen.",
                "„Paply-Gedanke“ auf den Home-Bildschirm ziehen.", "Ein Tipp aufs Widget nimmt auf, nochmal tippen beendet.").forEachIndexed { i, line ->
                Text("${i+1}. $line", modifier = Modifier.padding(top = 10.dp), style = MaterialTheme.typography.bodyMedium)
            }
        }
        Text("Die laufende Aufnahme steht in der Benachrichtigung: mit Zeit, „Fertig“ und „Verwerfen“. Aufnahmen werden nach der Umschrift sofort gelöscht, Text und Aufgaben bleiben.", style = MaterialTheme.typography.bodySmall, color = C.secondary)
        Pill("Hier ausprobieren", onCapture)
    }
}
