package com.paply.android.ui.thoughts

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.theme.PaplyThoughtType
import com.paply.thoughts.*
import kotlinx.coroutines.CancellationException
import java.time.Instant

@Composable
fun ThoughtDetailView(id: String, thoughts: List<Thought>, topics: List<Topic>, statuses: Map<String, ThoughtsRepository.Status>,
    repository: ThoughtsRepository, actions: ThoughtsActions, focusTask: String?, onBack: () -> Unit,
    onOpen: (String) -> Unit, onTopic: (String) -> Unit, onLink: (String) -> Unit,
    onSettings: () -> Unit, onDeleted: () -> Unit) {
    val thought = thoughts.firstOrNull { it.id == id }
    var editing by rememberSaveable(id) { mutableStateOf<String?>(null) }
    var draft by rememberSaveable(id) { mutableStateOf("") }
    var more by remember { mutableStateOf(false) }
    var deleting by rememberSaveable(id) { mutableStateOf(false) }
    var editingTask by rememberSaveable(id) { mutableStateOf<String?>(null) }
    var taskDraft by rememberSaveable(id) { mutableStateOf("") }
    val source by produceState<ThoughtSource?>(null, id, thought?.rev) {
        value = null
        try { value = repository.source(id) } catch (e: CancellationException) { throw e }
        catch (_: Exception) { value = null }
    }
    val listState = rememberSaveable(id, saver = LazyListState.Saver) { LazyListState() }
    val editorFocus = remember { FocusRequester() }
    LaunchedEffect(editing) { if (editing != null) { kotlinx.coroutines.delay(100); editorFocus.requestFocus() } }
    val lifecycle = LocalLifecycleOwner.current
    fun commit(after: () -> Unit = {}) {
        val field = editing; val text = draft
        if (field == null) { after(); return }
        actions.run {
            val current = repository.thought(id)
            val trimmed = text.trim()
            if (field == "title") { if (trimmed.isNotBlank() && trimmed != current?.title) repository.setTitle(id, trimmed) }
            else if (trimmed != current?.text.orEmpty()) repository.setText(id, trimmed)
            editing = null; after()
        }
    }
    val saveOnLeave by rememberUpdatedState({ commit() })
    DisposableEffect(lifecycle, id) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) saveOnLeave() }
        lifecycle.lifecycle.addObserver(observer)
        onDispose { lifecycle.lifecycle.removeObserver(observer); saveOnLeave() }
    }
    BackHandler(editing != null) { commit() }
    ThoughtToolbar("Gedanke", back = { commit(onBack) }, actions = {
        if (editing != null) TextButton(onClick = { commit() }) { Text("Fertig") }
        else if (thought != null) {
            IconButton(onClick = { actions.share(thought.shareText()) }) { Glyph(PaplyIcons.Share, "Teilen", C.greenBright) }
            Box {
                IconButton(onClick = { more = true }) { Glyph(PaplyIcons.More, "Mehr", C.greenBright) }
                DropdownMenu(more, { more = false }) {
                    DropdownMenuItem(text = { Text("Kopieren") }, onClick = { more = false; actions.copy(thought.shareText()) })
                    DropdownMenuItem(text = { Text("Thema ändern") }, onClick = { more = false; onTopic(id) })
                    if (thought.state == ThoughtState.done) DropdownMenuItem(text = { Text("Aufgabe hinzufügen") }, onClick = { more = false; editingTask = "new"; taskDraft = "" })
                    DropdownMenuItem(text = { Text("Verknüpfen …") }, onClick = { more = false; onLink(id) })
                    if (thought.state == ThoughtState.done || thought.state == ThoughtState.needsAttention)
                        DropdownMenuItem(text = { Text("Erneut ordnen") }, onClick = { more = false; actions.run { repository.reorganize(id) } })
                    DropdownMenuItem(text = { Text("Löschen", color = C.danger) }, onClick = { more = false; deleting = true })
                }
            }
        }
    })
    if (thought == null) {
        EmptyState("Gedanke nicht verfügbar", "Vielleicht liegt er in „Zuletzt gelöscht“.", PaplyIcons.MessageCircle)
        return
    }
    val related = remember(thoughts, id) {
        thoughts.filter { it.id != id }.mapNotNull { other ->
            thought.links.firstOrNull { it.target == other.id }?.let { Triple(other, it, false) }
                ?: other.links.firstOrNull { it.target == id }?.let { Triple(other, it, true) }
        }
    }
    LaunchedEffect(focusTask, thought.tasks.map { it.id }) {
        val index = thought.tasks.indexOfFirst { it.id == focusTask }
        if (index >= 0) listState.animateScrollToItem(index + 6)
    }
    LazyColumn(state = listState, contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item("topic") { TopicPill(topics.firstOrNull { it.id == thought.topicId }) { commit { onTopic(id) } } }
        item("date") { Text(dateLine(thought), color = C.secondary, style = MaterialTheme.typography.bodySmall) }
        item("title") {
            if (editing == "title") OutlinedTextField(draft, { draft = it }, label = { Text("Titel") }, textStyle = PaplyThoughtType.documentTitle, modifier = Modifier.fillMaxWidth().focusRequester(editorFocus))
            else Text(thought.displayTitle, style = PaplyThoughtType.documentTitle,
                modifier = Modifier.fillMaxWidth().semantics { heading() }.clickable(enabled = thought.state == ThoughtState.done) { commit { draft = thought.title.orEmpty(); editing = "title" } })
        }
        item("status") { ThoughtStatus(thought, statuses[id], actions, onSettings) }
        item("text") {
            if (editing == "text") OutlinedTextField(draft, { draft = it }, label = { Text("Text") }, minLines = 6,
                textStyle = MaterialTheme.typography.bodyLarge, modifier = Modifier.fillMaxWidth().focusRequester(editorFocus))
            else if (!thought.text.isNullOrBlank() || source != null) Text(thought.text ?: source?.text.orEmpty(),
                style = MaterialTheme.typography.bodyLarge, color = C.text.copy(alpha=.92f),
                modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp).clickable(enabled = thought.state == ThoughtState.done) { commit { draft = thought.text.orEmpty(); editing = "text" } })
            else Column(Modifier.fillMaxWidth().padding(vertical = 18.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                listOf(1f,.92f,.6f).forEach { width -> Box(Modifier.fillMaxWidth(width).height(12.dp).background(C.row, RoundedCornerShape(6.dp))) }
            }
        }
        if (thought.tasks.isNotEmpty()) item("task-label") { Text("Aufgaben", style = MaterialTheme.typography.titleSmall, color = C.secondary, modifier = Modifier.padding(top = 8.dp).semantics { heading() }) }
        items(thought.tasks, key = { it.id }) { task ->
            var taskMenu by remember { mutableStateOf(false) }
            Box {
                Row(Modifier.fillMaxWidth().background(if (focusTask == task.id) C.thoughtMint.copy(alpha=.1f) else Color.Transparent, RoundedCornerShape(10.dp))
                    .combinedClickable(onClick = { editingTask = task.id; taskDraft = task.text }, onLongClick = { taskMenu = true }), verticalAlignment = Alignment.CenterVertically) {
                    TaskCheck(task, id, actions)
                    Column(Modifier.weight(1f)) {
                        TaskText(task, actions)
                        dueText(task, thought, Instant.now())?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = C.secondary) }
                    }
                    IconButton(onClick = { taskMenu = true }) { Glyph(PaplyIcons.More, "Aufgabenaktionen: ${task.text}", C.tertiary, 18.dp) }
                }
                DropdownMenu(taskMenu, { taskMenu = false }) {
                    DropdownMenuItem(text = { Text("Bearbeiten") }, onClick = { taskMenu = false; editingTask = task.id; taskDraft = task.text })
                    DropdownMenuItem(text = { Text("Teilen") }, onClick = { taskMenu = false; actions.share(task.text) })
                    DropdownMenuItem(text = { Text("Löschen", color = C.danger) }, onClick = { taskMenu = false; actions.deleteTask(id, task.id) })
                }
            }
        }
        if (thought.state == ThoughtState.done) item("add-task") {
            TextButton(onClick = { editingTask = "new"; taskDraft = "" }) {
                Glyph(PaplyIcons.CirclePlus, tint = C.greenBright, size = 22.dp); Spacer(Modifier.width(12.dp)); Text("Aufgabe")
            }
        }
        if (related.isNotEmpty()) item("related-label") { Text("Verwandt", style = MaterialTheme.typography.titleSmall, color = C.secondary, modifier = Modifier.padding(top = 8.dp).semantics { heading() }) }
        items(related, key = { it.first.id }) { (other, link, incoming) ->
            var menu by remember { mutableStateOf(false) }
            Box {
                Row(Modifier.fillMaxWidth().combinedClickable(onClick = { commit { onOpen(other.id) } }, onLongClick = { menu = true }).padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Glyph(PaplyIcons.CornerDownRight, tint = C.thoughtMint, size = 17.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(other.displayTitle, style = MaterialTheme.typography.titleMedium)
                        Text(when (link.kind) { LinkKind.continues -> if (incoming) "Fortsetzung" else "Vorher"
                            LinkKind.sameMatter -> "Gleiches Anliegen"; LinkKind.changes -> if (incoming) "Neuer Stand" else "Alter Stand" } + " · " + compactDate(other.createdAt),
                            color = C.thoughtMint, style = MaterialTheme.typography.bodySmall)
                        Text(if (link.reason.isNotEmpty()) "„${link.reason}“" else "Von dir verknüpft", color = C.secondary, style = MaterialTheme.typography.bodyMedium)
                    }
                    IconButton(onClick = { menu = true }) { Glyph(PaplyIcons.More, "Verbindung bearbeiten", C.tertiary, 17.dp) }
                }
                DropdownMenu(menu, { menu = false }) { DropdownMenuItem(text = { Text("Verbindung lösen") },
                    onClick = { menu = false; actions.run { repository.removeLink(id, other.id) } }) }
            }
        }
        if (source != null) item("original") { key(id) { ThoughtOriginalView(source!!) } }
    }
    if (deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("Gedanken löschen?") },
        text = { Text("Er bleibt 30 Tage in „Zuletzt gelöscht“.") },
        confirmButton = { TextButton(onClick = { deleting = false; commit { actions.trash(id, onDeleted) } }) { Text("Löschen", color = C.danger) } },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text("Abbrechen") } })
    if (editingTask != null) AlertDialog(onDismissRequest = { editingTask = null }, title = { Text(if (editingTask == "new") "Neue Aufgabe" else "Aufgabe bearbeiten") },
        text = { OutlinedTextField(taskDraft, { taskDraft = it }, label = { Text("Aufgabe") }) },
        confirmButton = { TextButton(enabled = taskDraft.isNotBlank(), onClick = {
            val taskID = editingTask; val text = taskDraft
            actions.run { if (taskID == "new") repository.addTask(id, text) else if (taskID != null) repository.editTask(id, taskID, text); editingTask = null }
        }) { Text("Sichern") } }, dismissButton = { TextButton(onClick = { editingTask = null }) { Text("Abbrechen") } })
}

@Composable
fun ThoughtOriginalView(source: ThoughtSource) {
    var expanded by rememberSaveable(source.createdAt.toEpochMilli()) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TextButton(onClick = { expanded = !expanded }, modifier = Modifier.semantics { stateDescription = if (expanded) "aufgeklappt" else "zugeklappt" },
            contentPadding = PaddingValues(0.dp)) { Text(if (expanded) "Original ⌄" else "Original ›", color = C.secondary) }
        if (expanded) Surface(shape = RoundedCornerShape(14.dp), color = Color.White.copy(alpha=.05f)) {
            SelectionContainer { Text(source.text, color = C.text.copy(alpha=.78f), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.fillMaxWidth().padding(14.dp)) }
        }
    }
}
