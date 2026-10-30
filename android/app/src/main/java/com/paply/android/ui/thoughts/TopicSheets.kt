@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.paply.android.ui.thoughts

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paply.android.thoughts.AndroidTopicImageCodec
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.display.TopicImageFile
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream

@Composable
internal fun ThoughtSheet(title: String, onClose: () -> Unit, tall: Boolean = true,
    action: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onClose, sheetState = state, containerColor = C.forestDeep,
        contentColor = C.text, dragHandle = { BottomSheetDefaults.DragHandle(color = C.tertiary) }) {
        Column(Modifier.fillMaxWidth().then(if (tall) Modifier.fillMaxHeight(.88f) else Modifier).imePadding()) {
            if (title == "Zusammenführen" || LocalDensity.current.fontScale > 1.3f) {
                FlowRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = onClose) { Text("Abbrechen") }
                    action?.invoke()
                }
                Text(title, style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).semantics { heading() })
            } else Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onClose) { Text("Abbrechen") }
                Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(horizontal = 6.dp).semantics { heading() })
                action?.invoke()
            }
            content()
        }
    }
}

@Composable
fun TopicPickerSheet(thoughtID: String, topics: List<Topic>, thoughts: List<Thought>, actions: ThoughtsActions,
    onClose: () -> Unit, onNew: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    val current = thoughts.firstOrNull { it.id == thoughtID }?.topicId
    fun choose(id: String?) {
        if (saving) return
        saving = true
        actions.run { try { actions.repository.setTopic(thoughtID, id); onClose() } finally { saving = false } }
    }
    ThoughtSheet("Thema", onClose) {
        SearchField(query, { query = it }, "Thema suchen")
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            if (query.isBlank()) item {
                TopicChoiceRow(null, "Ohne Thema", null, current == null, { choose(null) }, enabled = !saving)
            }
            items(topics.filter { it.title.contains(query, true) }.sortedBy { it.title }, key = { it.id }) { topic ->
                TopicChoiceRow(topic, topic.title, thoughts.count { it.topicId == topic.id }, current == topic.id, { choose(topic.id) }, enabled = !saving)
            }
            item { TextButton(onClick = { onNew(query.trim()) }, enabled = !saving, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Glyph(PaplyIcons.CirclePlus, tint = C.greenBright, size = 22.dp)
                Spacer(Modifier.width(12.dp)); Text(if (query.isBlank()) "Neues Thema …" else "„$query“ anlegen …", modifier = Modifier.weight(1f))
            } }
        }
    }
}

@Composable
internal fun TopicChoiceRow(topic: Topic?, title: String, count: Int?, selected: Boolean, onClick: () -> Unit, enabled: Boolean = true) {
    Row(Modifier.fillMaxWidth().background(C.row).clickable(enabled = enabled, onClick = onClick)
        .padding(horizontal = 16.dp, vertical = 14.dp).semantics { this.selected = selected },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        TopicBadge(topic, gradient = topic != null)
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (count != null) Text("$count", color = C.tertiary, style = MaterialTheme.typography.bodyMedium)
        if (selected) Glyph(PaplyIcons.Check, tint = C.greenBright, size = 18.dp)
    }
}

@Composable
fun TopicEditor(topic: Topic?, actions: ThoughtsActions, onClose: () -> Unit, prefill: String = "",
    onSave: suspend (String, TopicIcon, String?, ByteArray?, Boolean) -> Unit) {
    var title by rememberSaveable(topic?.id) { mutableStateOf(topic?.title ?: prefill) }
    var note by rememberSaveable(topic?.id) { mutableStateOf(topic?.describedNote.orEmpty()) }
    var iconName by rememberSaveable(topic?.id) { mutableStateOf((topic?.icon ?: TopicIcon.sparkles).name) }
    val icon = TopicIcon.valueOf(iconName)
    var image by rememberSaveable(topic?.id) { mutableStateOf<ByteArray?>(null) }
    var imageChanged by rememberSaveable(topic?.id) { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var imageFailed by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val oldImage = LocalTopicAppearance.current.images[topic?.id]
    val shownImage = if (imageChanged) remember(image) { image?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) } } else oldImage
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            loading = true
            scope.launch {
                try {
                    val jpeg = withContext(Dispatchers.IO) {
                        val data = context.contentResolver.openInputStream(uri)?.use { input ->
                            ByteArrayOutputStream().use { output ->
                                val buffer = ByteArray(16 * 1024)
                                while (true) {
                                    val count = input.read(buffer); if (count < 0) break
                                    require(output.size() + count <= 30 * 1024 * 1024) { "image-too-large" }
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray()
                            }
                        }
                        data?.let { TopicImageFile.squareJPEG(it, AndroidTopicImageCodec()) }
                    }
                    if (jpeg == null) imageFailed = true else { image = jpeg; imageChanged = true }
                } catch (e: CancellationException) { throw e }
                catch (_: Exception) { imageFailed = true }
                finally { loading = false }
            }
        }
    }
    ThoughtSheet(if (topic == null) "Neues Thema" else "Thema", { if (!saving) onClose() }, action = {
        TextButton(enabled = title.isNotBlank() && !loading && !saving, onClick = {
            saving = true
            actions.run { try { onSave(title.trim(), icon, Topic.normalizedNote(note), image, imageChanged) } finally { saving = false } }
        }) { Text(if (saving) "Sichert …" else if (topic == null) "Anlegen" else "Sichern", fontWeight = FontWeight.SemiBold) }
    }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            PaplyCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    if (shownImage != null) Image(shownImage.asImageBitmap(), null, Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)))
                    else TopicBadge(Topic(id = "_draft", title = title, icon = icon, owner = Owner.user), 44.dp, gradient = true)
                    OutlinedTextField(title, { title = it }, label = { Text("Name") }, singleLine = true,
                        textStyle = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                }
            }
            Section("Worum geht's?", if (note.length > Topic.maxNoteLength - 40) "Noch ${Topic.maxNoteLength - note.length} Zeichen" else null) {
                OutlinedTextField(note, { note = it.take(Topic.maxNoteLength) },
                    placeholder = { Text("Namen, Firmen, Personen – damit Paply Gedanken richtig zuordnet", style = MaterialTheme.typography.bodyMedium) },
                    minLines = 2, maxLines = 5, modifier = Modifier.fillMaxWidth(), textStyle = MaterialTheme.typography.bodyLarge)
            }
            Section("Bild", "Ein Foto, z. B. ein Logo, ersetzt das Symbol. Es bleibt auf diesem Gerät und geht nie an die KI.") {
                TextButton(enabled = !loading && !saving, onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, modifier = Modifier.fillMaxWidth()) {
                    Text(if (loading) "Bild wird geladen …" else "Bild wählen …", modifier = Modifier.weight(1f))
                    Glyph(PaplyIcons.Camera, tint = C.greenBright)
                }
                if (shownImage != null) TextButton(onClick = { image = null; imageChanged = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Bild entfernen", color = C.danger, modifier = Modifier.weight(1f)); Glyph(PaplyIcons.Trash, tint = C.danger)
                }
            }
            Section("Symbol", if (shownImage != null) "Erscheint, wo kein Bild Platz hat, z. B. in der Benachrichtigung." else null) {
                FlowRow(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    TopicIcon.entries.forEach { choice ->
                        val selected = icon == choice
                        Box(Modifier.size(48.dp).clip(CircleShape).then(if (selected) Modifier.background(C.thoughtFill) else Modifier.background(C.row))
                            .clickable { iconName = choice.name }.semantics { contentDescription = choice.spokenName; this.selected = selected }, contentAlignment = Alignment.Center) {
                            Icon(choice.glyph, null, Modifier.size(22.dp), tint = if (selected) C.forest else C.text)
                        }
                    }
                }
            }
        }
    }
    if (imageFailed) AlertDialog(onDismissRequest = { imageFailed = false }, title = { Text("Bild ließ sich nicht öffnen") },
        text = { Text("Bitte ein anderes Foto wählen.") }, confirmButton = { TextButton(onClick = { imageFailed = false }) { Text("OK") } })
}

@Composable
fun TopicMergeSheet(ids: List<String>, topics: List<Topic>, thoughts: List<Thought>, actions: ThoughtsActions, onClose: () -> Unit) {
    val multiple = ids.size >= 2
    val candidates = if (multiple) topics.filter { it.id in ids } else topics.filter { it.id !in ids }
    var chosen by rememberSaveable(ids) { mutableStateOf(if (multiple) candidates.maxByOrNull { topic -> thoughts.count { it.topicId == topic.id } }?.id else null) }
    ThoughtSheet(if (multiple) "Zusammenführen" else "Zusammenführen mit …", onClose, action = {
        if (multiple) TextButton(enabled = chosen != null, onClick = {
            val target = chosen ?: return@TextButton
            actions.withUndo("Zusammengeführt", 5) { val undo = actions.repository.mergeTopics(ids, target); onClose(); undo }
        }) { Text("Zusammenführen", fontWeight = FontWeight.SemiBold) }
    }) {
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            item { Text(if (multiple) "Welcher Name bleibt?" else "Die Gedanken kommen zum gewählten Thema.", color = C.secondary, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(bottom = 14.dp)) }
            items(candidates.sortedBy { it.title }, key = { it.id }) { topic ->
                TopicChoiceRow(topic, topic.title, thoughts.count { it.topicId == topic.id }, chosen == topic.id, {
                    if (multiple) chosen = topic.id
                    else actions.withUndo("Zusammengeführt", 5) { val undo = actions.repository.mergeTopics(ids, topic.id); onClose(); undo }
                })
            }
            item { Text("Alle Gedanken kommen unter dieses Thema. Danach lässt es sich widerrufen.", color = C.secondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp)) }
        }
    }
}

@Composable
fun TopicActionsSheet(topic: Topic, count: Int, actions: ThoughtsActions, onClose: () -> Unit,
    onEdit: () -> Unit, onMerge: () -> Unit) {
    var rename by rememberSaveable { mutableStateOf(false) }
    var draft by rememberSaveable { mutableStateOf(topic.title) }
    var remove by rememberSaveable { mutableStateOf(false) }
    ThoughtSheet(topic.title, onClose, tall = false) {
        SettingsItem("Umbenennen", icon = PaplyIcons.Pencil, onClick = { rename = true })
        SettingsItem("Bild oder Symbol", icon = PaplyIcons.Camera, onClick = onEdit)
        SettingsItem("Worum geht's?", value = topic.describedNote, onClick = onEdit)
        SettingsItem("Zusammenführen mit …", icon = PaplyIcons.Merge, onClick = onMerge)
        TextButton(onClick = { remove = true }, modifier = Modifier.fillMaxWidth().padding(8.dp)) { Text("Thema löschen", color = C.danger) }
    }
    if (rename) AlertDialog(onDismissRequest = { rename = false }, title = { Text("Thema umbenennen") },
        text = { OutlinedTextField(draft, { draft = it }, label = { Text("Name") }) },
        confirmButton = { TextButton(enabled = draft.isNotBlank(), onClick = { actions.run { actions.repository.renameTopic(topic.id, draft); rename = false; onClose() } }) { Text("Umbenennen") } },
        dismissButton = { TextButton(onClick = { rename = false }) { Text("Abbrechen") } })
    if (remove) DeleteTopicDialog(topic, count, { remove = false }) {
        actions.run { actions.repository.deleteTopic(topic.id); remove = false; onClose() }
    }
}

@Composable
internal fun DeleteTopicDialog(topic: Topic, count: Int, onClose: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(onDismissRequest = onClose, title = { Text("„${topic.title}“ löschen?") },
        text = { Text(if (count == 1) "1 Gedanke bleibt, nur ohne Thema." else "$count Gedanken bleiben, nur ohne Thema.") },
        confirmButton = { TextButton(onClick = onDelete) { Text("Thema löschen", color = C.danger) } },
        dismissButton = { TextButton(onClick = onClose) { Text("Abbrechen") } })
}

@Composable
fun LinkPickerSheet(thoughtID: String, thoughts: List<Thought>, topics: List<Topic>, repository: ThoughtsRepository,
    actions: ThoughtsActions, onClose: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val hits by searchResults(repository, query, thoughts, topics)
    val source = thoughts.firstOrNull { it.id == thoughtID }
    val linked = thoughts.filter { it.links.any { link -> link.target == thoughtID } }.map { it.id }.toSet() + source?.links.orEmpty().map { it.target }
    val candidates = (if (query.isBlank()) thoughts.filter { it.state == ThoughtState.done }.take(40)
        else hits.mapNotNull { hit -> thoughts.firstOrNull { it.id == hit.thoughtID } }).filter { it.id != thoughtID && it.id !in linked }
    ThoughtSheet("Verknüpfen", onClose) {
        SearchField(query, { query = it }, "Gedanken suchen")
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            if (query.isBlank()) item { ThoughtSectionTitle("Zuletzt") }
            if (candidates.isEmpty()) item { EmptyState("Keine Gedanken", "Keine weiteren passenden Gedanken gefunden.", PaplyIcons.Link) }
            items(candidates, key = { it.id }) { thought ->
                SettingsItem(thought.displayTitle, value = thought.previewLine, onClick = { actions.run { repository.addLink(thoughtID, thought.id); onClose() } }, trailing = { TopicBadge(topics.firstOrNull { it.id == thought.topicId }) })
            }
        }
    }
}
