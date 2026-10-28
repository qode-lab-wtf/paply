package com.paply.android.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import com.paply.android.settings.SettingsRepository
import com.paply.android.history.HistoryEntry
import com.paply.android.history.HistoryStatus
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import java.text.DateFormat
import java.util.Date
import java.util.Locale

fun historyDate(time: Long): String = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.GERMAN).format(Date(time))
fun duration(ms: Long): String = String.format(Locale.GERMAN, "%.2f s", ms / 1000.0)

@Composable
fun DictationScreen(entries: List<HistoryEntry>, status: SetupStatus, setup: @Composable () -> Unit,
    copy: (String) -> Unit, detail: (HistoryEntry) -> Unit, delete: (HistoryEntry) -> Unit, deleteAll: () -> Unit,
    keyboard: () -> Unit, error: String?, retryLoad: () -> Unit,
) {
    var confirmClear by remember { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item("setup") { setup() }
        item("keyboard-status") {
            PaplyCard(radius = 22.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Glyph(PaplyIcons.Keyboard, tint = if (status.keyboardSelected) C.greenBright else C.tertiary, size = 28.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(if (status.keyboardSelected) "Paply ist bereit" else if (status.keyboardEnabled) "Paply ist aktiviert" else "Paply ist aus", style = MaterialTheme.typography.titleLarge)
                        Text(if (status.keyboardSelected) "Tippe in einem Textfeld auf Paply und sprich."
                            else if (status.keyboardEnabled) "Wähle Paply als Tastatur, um zu diktieren." else "Aktiviere Paply in den Tastatureinstellungen.",
                            color = C.secondary, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                Box(Modifier.fillMaxWidth().padding(top = 16.dp), contentAlignment = Alignment.Center) {
                    Pill(if (status.keyboardSelected) "Tastatur einrichten" else if (status.keyboardEnabled) "Tastatur auswählen" else "Tastatur aktivieren", keyboard)
                }
            }
        }
        item("history-title") {
            Row(Modifier.fillMaxWidth().padding(top = 10.dp, start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Verlauf", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
                if (entries.isNotEmpty()) TextButton(onClick = { confirmClear = true }) { Text("Alles löschen", color = C.danger) }
            }
        }
        if (error != null) item("load-error") {
            PaplyCard { Text(error, color = C.beak); TextButton(onClick = retryLoad) { Text("Erneut versuchen") } }
        } else if (entries.isEmpty()) item("empty") {
            PaplyCard(radius = 16.dp) {
                Text("Noch keine Diktate. Wähle in einem Textfeld Paply als Tastatur und sprich.", color = C.text.copy(alpha = 0.6f), style = MaterialTheme.typography.bodyMedium)
            }
        }
        items(entries, key = { it.id }) { entry -> HistoryRow(entry, { copy(entry.text) }, { detail(entry) }, { delete(entry) }) }
        if (entries.isNotEmpty()) item("history-help") {
            Text("Antippen kopiert den Text. ⓘ zeigt Rohtext, Polieren und Zeiten. Lange drücken: löschen.", style = MaterialTheme.typography.bodySmall,
                color = C.text.copy(alpha = 0.45f), modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("Ganzen Verlauf löschen?") },
        text = { Text("Alle Diktate auf diesem Gerät werden entfernt. Das lässt sich nicht widerrufen.") },
        confirmButton = { TextButton(onClick = { deleteAll(); confirmClear = false }) { Text("Alles löschen", color = C.danger) } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Abbrechen") } })
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HistoryRow(entry: HistoryEntry, copy: () -> Unit, detail: () -> Unit, delete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Surface(shape = RoundedCornerShape(16.dp), color = Color.White.copy(alpha = 0.05f)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                Column(Modifier.fillMaxWidth().combinedClickable(onClick = copy, onLongClick = { menu = true },
                    onClickLabel = "Text kopieren", onLongClickLabel = "Aktionen")
                    .padding(start = 15.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(entry.text.ifEmpty { entry.error ?: if (entry.status == HistoryStatus.PENDING) "Wird verarbeitet …" else "(leer)" },
                        maxLines = 2, style = MaterialTheme.typography.bodyLarge,
                        color = if (entry.status == HistoryStatus.FAILED && entry.text.isEmpty()) C.danger else C.text)
                    Text(historyDate(entry.createdAt) + " · " + duration(entry.durationMs), style = MaterialTheme.typography.bodySmall, color = C.text.copy(alpha = 0.45f))
                    if (entry.status != HistoryStatus.OK) Text(if (entry.status == HistoryStatus.FAILED) "Fehlgeschlagen" else "Ausstehend",
                        color = if (entry.status == HistoryStatus.FAILED) C.beak else C.secondary, style = MaterialTheme.typography.bodySmall)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Kopieren") }, onClick = { copy(); menu = false })
                    DropdownMenuItem(text = { Text("Löschen", color = C.danger) }, onClick = { delete(); menu = false })
                }
            }
            IconButton(onClick = detail) { Glyph(PaplyIcons.Info, "Details", C.text.copy(alpha = 0.5f)) }
        }
    }
}

/** onRetry is deliberately an integration callback. UI never starts transcription itself. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HistoryDetailScreen(entry: HistoryEntry?, copy: (String) -> Unit, share: (String) -> Unit, onRetry: (HistoryEntry) -> Unit) {
    if (entry == null) { EmptyState("Nicht mehr im Verlauf", "Dieses Diktat wurde entfernt.", PaplyIcons.Clock); return }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Section("Text") { Copyable(entry.text, "nichts", copy) }
        Section("Rohtext") { Copyable(entry.raw, "leer", copy) }
        Section("Polieren") {
            SettingsItem("Ergebnis", value = if (entry.polished.isNotEmpty()) "poliert" else "unpoliert")
            if (entry.status != HistoryStatus.OK && entry.polished.isNotEmpty()) Copyable(entry.polished, "leer", copy)
        }
        if (entry.status != HistoryStatus.OK || entry.error != null) Section(if (entry.status == HistoryStatus.FAILED) "Fehler" else "Status") {
            Text(entry.error ?: if (entry.status == HistoryStatus.PENDING && entry.text.isNotBlank()) "Text ist gesichert und wartet auf das Einsetzen."
                else if (entry.status == HistoryStatus.PENDING) "Wird verarbeitet …" else "Verarbeitung fehlgeschlagen.",
                color = if (entry.status == HistoryStatus.FAILED) C.danger else C.beak, modifier = Modifier.padding(16.dp))
            if (entry.status == HistoryStatus.FAILED) TextButton(onClick = { onRetry(entry) }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Erneut versuchen") }
        }
        Section("Zeiten") { SettingsItem("Audio", value = duration(entry.durationMs)) }
        Section("Sonst") {
            SettingsItem("Quelle", value = "Tastatur")
            Hairline()
            SettingsItem("Sprachen", value = entry.language?.let(SettingsRepository::languageName) ?: "–")
            Hairline()
            SettingsItem("Zeit", value = historyDate(entry.createdAt))
        }
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Pill("Kopieren", { copy(entry.text) }, enabled = entry.text.isNotEmpty())
            Pill("Teilen", { share(entry.text) }, prominent = false, enabled = entry.text.isNotEmpty())
        }
    }
}

@Composable
private fun Copyable(text: String, empty: String, copy: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(16.dp)) {
        SelectionContainer { Text(text.ifEmpty { empty }, color = if (text.isEmpty()) C.secondary else C.text) }
        if (text.isNotEmpty()) TextButton(onClick = { copy(text) }) { Text("Kopieren") }
    }
}
