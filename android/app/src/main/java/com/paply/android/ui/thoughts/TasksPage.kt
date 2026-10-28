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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.display.TaskAgenda
import kotlinx.coroutines.delay
import java.time.Instant

@Composable
fun TasksPage(thoughts: List<Thought>, topics: List<Topic>, loaded: Boolean, actions: ThoughtsActions,
    onSettings: () -> Unit, onCapture: () -> Unit, onOpen: (String, String) -> Unit) {
    // Refresh dates even if this page stays open over midnight or the timezone changes.
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) { while (true) { now = Instant.now(); delay(30_000) } }
    val agenda = remember(thoughts, now) { TaskAgenda(thoughts, now) }
    var showDone by rememberSaveable { mutableStateOf(false) }
    var allDone by rememberSaveable { mutableStateOf(false) }
    var editThought by rememberSaveable { mutableStateOf<String?>(null) }
    var editTask by rememberSaveable { mutableStateOf<String?>(null) }
    var draft by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize()) {
        ThoughtToolbar("Aufgaben", beta = true, large = true, actions = {
            IconButton(onClick = onSettings) { Glyph(PaplyIcons.Settings, "Einstellungen", C.greenBright) }
        })
        Box(Modifier.weight(1f)) {
            if (!loaded) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else if (agenda.openCount == 0 && agenda.allDone.isEmpty()) Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                EmptyState("Noch keine Aufgaben", "Aufgaben entstehen aus deinen Gedanken. Sag einfach „Ich muss …“ – Paply hält sie hier fest.", PaplyIcons.ListChecks)
                Pill("Gedanke aufnehmen", onCapture)
            } else LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                if (agenda.openCount == 0) item { EmptyState("Alles erledigt", "Neue Aufgaben entstehen aus deinen Gedanken.", PaplyIcons.Check) }
                TaskAgenda.Group.entries.forEach { group ->
                    val members = agenda.items(group)
                    if (members.isNotEmpty()) {
                        item("group:$group") { ThoughtSectionTitle(when(group) { TaskAgenda.Group.overdue -> "Überfällig"; TaskAgenda.Group.today -> "Heute"
                            TaskAgenda.Group.upcoming -> "Demnächst"; TaskAgenda.Group.someday -> "Irgendwann" }, members.size,
                            if (group == TaskAgenda.Group.overdue) C.beak else C.text) }
                        items(members, key = { it.id }) { item ->
                            TaskAgendaRow(item, topics.firstOrNull { it.id == item.thought.topicId }, now, actions, { onOpen(item.thought.id, item.task.id) },
                                onEdit = { editThought = item.thought.id; editTask = item.task.id; draft = item.task.text })
                        }
                    }
                }
                if (agenda.allDone.isNotEmpty()) {
                    item("done-header") {
                        TextButton(onClick = { showDone = !showDone }, contentPadding = PaddingValues(0.dp)) {
                            ThoughtSectionTitle(if (showDone) "Erledigt ⌄" else "Erledigt ›", if (allDone) agenda.allDone.size else agenda.recentlyDone.size)
                        }
                    }
                    if (showDone) {
                        val shown = if (allDone) agenda.allDone else agenda.recentlyDone
                        items(shown, key = { "done:${it.id}" }) { item ->
                            TaskAgendaRow(item, topics.firstOrNull { it.id == item.thought.topicId }, now, actions, { onOpen(item.thought.id, item.task.id) },
                                onEdit = { editThought = item.thought.id; editTask = item.task.id; draft = item.task.text })
                        }
                        if (shown.isEmpty()) item { Text("In den letzten 7 Tagen nichts erledigt.", color = C.secondary, style = MaterialTheme.typography.bodySmall) }
                        if (!allDone && agenda.allDone.size > agenda.recentlyDone.size) item {
                            TextButton(onClick = { allDone = true }) { Text("Alle erledigten (${agenda.allDone.size})") }
                        }
                        item { Text(if (allDone) "Alle erledigten Aufgaben, neueste zuerst." else "Erledigt in den letzten 7 Tagen.", color = C.secondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(12.dp)) }
                    }
                }
            }
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), contentAlignment = Alignment.CenterEnd) { CaptureButton(onCapture) }
    }
    if (editTask != null) AlertDialog(onDismissRequest = { editTask = null }, title = { Text("Aufgabe bearbeiten") },
        text = { OutlinedTextField(draft, { draft = it }, label = { Text("Aufgabe") }) },
        confirmButton = { TextButton(enabled = draft.isNotBlank(), onClick = {
            val thoughtID = editThought; val taskID = editTask
            if (thoughtID != null && taskID != null) actions.run { actions.repository.editTask(thoughtID, taskID, draft); editTask = null }
        }) { Text("Sichern") } }, dismissButton = { TextButton(onClick = { editTask = null }) { Text("Abbrechen") } })
}

@Composable
private fun TaskAgendaRow(item: TaskAgenda.Item, topic: Topic?, now: Instant, actions: ThoughtsActions,
    onOpen: () -> Unit, onEdit: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.StartToEnd) actions.toggle(item.thought.id, item.task)
        if (value == SwipeToDismissBoxValue.EndToStart) actions.deleteTask(item.thought.id, item.task.id)
        false
    })
    SwipeToDismissBox(swipe, backgroundContent = {
        SwipeActionBackground(swipe, if (item.task.done) "Wieder öffnen" else "Erledigt", "Löschen")
    }) {
        Box {
            Row(Modifier.fillMaxWidth().background(C.row).combinedClickable(onClick = onOpen, onLongClick = { menu = true }).padding(end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.Top) {
                TaskCheck(item.task, item.thought.id, actions)
                Column(Modifier.weight(1f).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    TaskText(item.task, actions)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        TopicBadge(topic, 20.dp)
                        Text(item.thought.displayTitle, color = topicTint(topic?.id).ink, style = MaterialTheme.typography.bodySmall,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    }
                    dueText(item.task, item.thought, now)?.let { due -> Text(due, style = MaterialTheme.typography.bodySmall,
                        color = if (TaskAgenda.group(item.task.dueAt, now) == TaskAgenda.Group.overdue && !item.task.done) C.beak else C.secondary) }
                }
                IconButton(onClick = { menu = true }) { Glyph(PaplyIcons.More, "Aufgabenaktionen: ${item.task.text}", C.tertiary, 17.dp) }
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(text = { Text(if (item.task.done || actions.pending[item.task.id] == true) "Wieder öffnen" else "Erledigt") }, onClick = { menu = false; actions.toggle(item.thought.id, item.task) })
                DropdownMenuItem(text = { Text("Bearbeiten") }, onClick = { menu = false; onEdit() })
                DropdownMenuItem(text = { Text("Gedanken öffnen") }, onClick = { menu = false; onOpen() })
                DropdownMenuItem(text = { Text("Teilen") }, onClick = { menu = false; actions.share(item.task.text) })
                DropdownMenuItem(text = { Text("Löschen", color = C.danger) }, onClick = { menu = false; actions.deleteTask(item.thought.id, item.task.id) })
            }
        }
    }
}

/** iOS badge: only overdue and today's open tasks contribute. */
@Composable
fun ThoughtsTaskTabIcon(repository: com.paply.android.thoughts.ThoughtsRepository, selected: Boolean) {
    val thoughts by repository.thoughts.collectAsState()
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) { while (true) { now = Instant.now(); delay(30_000) } }
    val count = remember(thoughts, now) { TaskAgenda.urgentCount(thoughts, now) }
    BadgedBox(badge = { if (count > 0) Badge(containerColor = C.beak, contentColor = C.forest) { Text("$count") } }) {
        Glyph(PaplyIcons.ListChecks, tint = if (selected) C.thoughtMint else C.secondary)
    }
}
