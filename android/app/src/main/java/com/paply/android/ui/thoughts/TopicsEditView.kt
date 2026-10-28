@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.paply.android.ui.thoughts

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.local.TopicIndex
import com.paply.thoughts.model.TopicSuggestion
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil

@Composable
fun TopicsEditView(repository: ThoughtsRepository, actions: ThoughtsActions, thoughts: List<Thought>, topics: List<Topic>,
    onBack: () -> Unit, onEdit: (Topic) -> Unit, onNew: () -> Unit, onMerge: (List<String>) -> Unit) {
    val suggestions by repository.suggestions.collectAsStateWithLifecycle()
    var selecting by rememberSaveable { mutableStateOf(false) }
    var selected by rememberSaveable { mutableStateOf(listOf<String>()) }
    var deletingID by rememberSaveable { mutableStateOf<String?>(null) }
    var acceptingID by rememberSaveable { mutableStateOf<String?>(null) }
    ThoughtToolbar("Themen", onBack, actions = {
        TextButton(onClick = { selecting = !selecting; selected = emptyList() }) { Text(if (selecting) "Fertig" else "Auswählen") }
    })
    val sorted = topics.sortedBy { it.title.lowercase() }
    val active = sorted.filter { topic -> TopicIndex.isActive(topic, thoughts.count { it.topicId == topic.id }) }
    val provisional = sorted - active.toSet()
    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (suggestions.isNotEmpty()) {
            item { ThoughtSectionTitle("Vorschläge") }
            items(suggestions.take(2), key = { it.id }) { suggestion ->
                val a = topics.firstOrNull { it.id == suggestion.a }; val b = topics.firstOrNull { it.id == suggestion.b }
                if (a != null && b != null) PaplyCard {
                    Text("„${a.title}“ und „${b.title}“ zusammenführen?", style = MaterialTheme.typography.titleMedium)
                    if (suggestion.reason.isNotBlank()) Text(suggestion.reason, style = MaterialTheme.typography.bodyMedium, color = C.secondary, modifier = Modifier.padding(top = 8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Pill("Zusammenführen", { acceptingID = suggestion.id })
                        Pill("Nein", { actions.run { repository.declineSuggestion(suggestion) } }, prominent = false)
                    }
                }
            }
        }
        item { ThoughtSectionTitle("Themen", active.size) }
        items(active, key = { it.id }) { topic ->
            ManageTopicRow(topic, thoughts.count { it.topicId == topic.id }, false, selecting, topic.id in selected, actions,
                onClick = { if (selecting) selected = if (topic.id in selected) selected - topic.id else selected + topic.id else onEdit(topic) },
                onDelete = { deletingID = topic.id }, onMerge = { onMerge(listOf(topic.id)) })
        }
        if (active.isEmpty()) item { Text("Themen entstehen von selbst, sobald zwei Gedanken zusammenpassen.", color = C.secondary, style = MaterialTheme.typography.bodySmall) }
        if (provisional.isNotEmpty()) {
            item { ThoughtSectionTitle("Neu", provisional.size) }
            items(provisional, key = { it.id }) { topic ->
                ManageTopicRow(topic, thoughts.count { it.topicId == topic.id }, true, selecting, topic.id in selected, actions,
                    onClick = { if (selecting) selected = if (topic.id in selected) selected - topic.id else selected + topic.id else onEdit(topic) },
                    onDelete = { deletingID = topic.id }, onMerge = { onMerge(listOf(topic.id)) })
            }
            item { Text("Vorläufige Themen mit einem Gedanken. Als Chip erscheinen sie, sobald ein zweiter dazukommt – oder wenn du sie behältst oder beschreibst. Umbenennen allein behält sie nicht.", color = C.secondary, style = MaterialTheme.typography.bodySmall) }
        }
        item {
            if (selecting) Pill(if (selected.size >= 2) "${selected.size} zusammenführen" else "Zusammenführen", { onMerge(selected) }, enabled = selected.size >= 2)
            else TextButton(onClick = onNew) { Glyph(PaplyIcons.CirclePlus, tint = C.greenBright); Spacer(Modifier.width(10.dp)); Text("Neues Thema …") }
        }
    }
    topics.firstOrNull { it.id == deletingID }?.let { topic ->
        DeleteTopicDialog(topic, thoughts.count { it.topicId == topic.id }, { deletingID = null }) {
            actions.run { repository.deleteTopic(topic.id); deletingID = null }
        }
    }
    suggestions.firstOrNull { it.id == acceptingID }?.let { suggestion ->
        AlertDialog(onDismissRequest = { acceptingID = null }, title = { Text("Themen zusammenführen?") },
            text = { Text("Alle Gedanken kommen unter „${suggestion.name ?: topics.firstOrNull { it.id == suggestion.a }?.title.orEmpty()}“. Danach lässt es sich widerrufen.") },
            confirmButton = { TextButton(onClick = {
                actions.withUndo("Zusammengeführt", 5) { val undo = repository.acceptSuggestion(suggestion); acceptingID = null; undo }
            }) { Text("Zusammenführen") } }, dismissButton = { TextButton(onClick = { acceptingID = null }) { Text("Abbrechen") } })
    }
}

@Composable
private fun ManageTopicRow(topic: Topic, count: Int, provisional: Boolean, selecting: Boolean, selected: Boolean,
    actions: ThoughtsActions, onClick: () -> Unit, onDelete: () -> Unit, onMerge: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { if (it == SwipeToDismissBoxValue.EndToStart) onDelete(); false })
    SwipeToDismissBox(swipe, enableDismissFromStartToEnd = false, backgroundContent = {
        SwipeActionBackground(swipe, "", "Löschen")
    }) {
        Surface(shape = RoundedCornerShape(14.dp), color = C.row) {
            Row(Modifier.fillMaxWidth().combinedClickable(onClick = onClick, onLongClick = { menu = true }).padding(start = 14.dp, end = 6.dp, top = 10.dp, bottom = 10.dp)
                .semantics { this.selected = selected }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (selecting) Checkbox(selected, onCheckedChange = null)
                TopicBadge(topic, 32.dp, gradient = true)
                Column(Modifier.weight(1f)) {
                    Text(topic.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    topic.describedNote?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
                if (provisional && !selecting) Pill("Behalten", { actions.run { actions.repository.keepProvisional(topic.id) } })
                else Text("$count", color = C.tertiary, style = MaterialTheme.typography.bodyMedium)
                if (!selecting) Box {
                    IconButton(onClick = { menu = true }) { Glyph(PaplyIcons.More, "Themenaktionen: ${topic.title}", C.secondary, 18.dp) }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text("Bearbeiten") }, onClick = { menu = false; onClick() })
                        DropdownMenuItem(text = { Text("Zusammenführen mit …") }, onClick = { menu = false; onMerge() })
                        DropdownMenuItem(text = { Text(if (provisional) "Auflösen" else "Löschen", color = C.danger) }, onClick = { menu = false; onDelete() })
                    }
                }
            }
        }
    }
}

@Composable
fun RecentlyDeletedView(deleted: List<Thought>, topics: List<Topic>, actions: ThoughtsActions, onBack: () -> Unit) {
    var purgeID by rememberSaveable { mutableStateOf<String?>(null) }
    var purgeAll by rememberSaveable { mutableStateOf(false) }
    ThoughtToolbar("Zuletzt gelöscht", onBack, actions = {
        if (deleted.isNotEmpty()) TextButton(onClick = { purgeAll = true }) { Text("Alle löschen", color = C.danger) }
    })
    if (deleted.isEmpty()) EmptyState("Nichts gelöscht", "Gelöschte Gedanken bleiben hier 30 Tage, dann werden sie endgültig entfernt.", PaplyIcons.Trash)
    else LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        items(deleted, key = { it.id }) { thought ->
            var menu by remember { mutableStateOf(false) }
            val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                if (value == SwipeToDismissBoxValue.StartToEnd) actions.run("Wiederhergestellt") { actions.repository.restore(thought.id) }
                if (value == SwipeToDismissBoxValue.EndToStart) purgeID = thought.id
                false
            })
            SwipeToDismissBox(swipe, backgroundContent = {
                SwipeActionBackground(swipe, "Wiederherstellen", "Endgültig löschen")
            }) {
                Box {
                    Row(Modifier.fillMaxWidth().background(C.row).combinedClickable(onClick = { menu = true }, onLongClick = { menu = true }).padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        TopicBadge(topics.firstOrNull { it.id == thought.topicId })
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(thought.displayTitle, style = MaterialTheme.typography.titleMedium)
                            Text(thought.previewLine, style = MaterialTheme.typography.bodyMedium, color = C.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            val days = ceil(Duration.between(Instant.now(), (thought.deletedAt ?: Instant.now()).plusSeconds(30L*86400)).seconds / 86400.0).toInt().coerceAtLeast(0)
                            Text(if (days == 1) "noch 1 Tag" else "noch $days Tage", style = MaterialTheme.typography.bodySmall, color = C.tertiary)
                        }
                        IconButton(onClick = { menu = true }) { Glyph(PaplyIcons.More, "Gelöschten Gedanken verwalten", C.secondary, 18.dp) }
                    }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text("Wiederherstellen") }, onClick = { menu = false; actions.run("Wiederhergestellt") { actions.repository.restore(thought.id) } })
                        DropdownMenuItem(text = { Text("Endgültig löschen", color = C.danger) }, onClick = { menu = false; purgeID = thought.id })
                    }
                }
            }
        }
        item { Text("Gelöschte Gedanken werden nach 30 Tagen endgültig entfernt.", color = C.secondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp)) }
    }
    if (purgeID != null || purgeAll) AlertDialog(onDismissRequest = { purgeID = null; purgeAll = false },
        title = { Text(if (purgeAll) "Alle endgültig löschen?" else "Endgültig löschen?") },
        text = { Text(if (purgeAll) "Text und Aufgaben werden sofort entfernt – Themen, die dann leer sind, ebenso. Das lässt sich nicht widerrufen." else "Text und Aufgaben werden sofort entfernt. Das lässt sich nicht widerrufen.") },
        confirmButton = { TextButton(onClick = {
            val id = purgeID; val all = purgeAll
            actions.run { if (all) actions.repository.purgeAllDeleted() else if (id != null) actions.repository.permanentlyDelete(id)
                purgeID = null; purgeAll = false }
        }) { Text(if (purgeAll) "Alle löschen" else "Endgültig löschen", color = C.danger) } },
        dismissButton = { TextButton(onClick = { purgeID = null; purgeAll = false }) { Text("Abbrechen") } })
}
