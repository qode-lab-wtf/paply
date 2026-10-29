package com.paply.android.ui.thoughts

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.spring
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.CaptureActivity
import com.paply.android.ThoughtService
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.local.TopicIndex
import com.paply.thoughts.model.SearchHit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import java.time.Instant

/** Separate saved navigation per tab, composed within PaplyApp's existing state holder. */
@Composable
fun ThoughtsTab(repository: ThoughtsRepository, actions: ThoughtsActions, tasksTab: Boolean,
    setup: @Composable () -> Unit, onSettings: () -> Unit, onTileSetup: () -> Unit,
    focusID: String? = null, onFocusConsumed: (String) -> Unit = {}, taskDestination: com.paply.android.ui.tasks.TaskOpenRequest? = null, setupProgress: Pair<Int, Int> = 0 to 6) {
    val thoughts by repository.thoughts.collectAsStateWithLifecycle()
    val topics by repository.topics.collectAsStateWithLifecycle()
    val deleted by repository.deleted.collectAsStateWithLifecycle()
    val statuses by repository.status.collectAsStateWithLifecycle()
    val loaded by repository.isLoaded.collectAsStateWithLifecycle()
    val error by repository.error.collectAsStateWithLifecycle()
    var route by rememberSaveable { mutableStateOf("home") }
    var origin by rememberSaveable { mutableStateOf("home") }
    var path by rememberSaveable { mutableStateOf(listOf<String>()) }
    var focusTask by rememberSaveable { mutableStateOf<String?>(null) }
    var filter by rememberSaveable { mutableStateOf("all") }
    var mapMode by rememberSaveable { mutableStateOf(true) }
    var mapFocus by rememberSaveable { mutableStateOf<String?>(null) }
    var listQuery by rememberSaveable { mutableStateOf("") }
    var sheet by rememberSaveable { mutableStateOf<String?>(null) }
    var sheetID by rememberSaveable { mutableStateOf("") }
    var newTopicPrefill by rememberSaveable { mutableStateOf("") }
    var createdTopicID by rememberSaveable { mutableStateOf<String?>(null) }
    var mergeIDs by rememberSaveable { mutableStateOf(listOf<String>()) }
    val context = LocalContext.current
    fun open(id: String, task: String? = null) {
        if (route != "detail") { origin = route; path = emptyList() }
        path = path + id; focusTask = task; route = "detail"
    }
    fun back() {
        if (route == "detail" && path.size > 1) path = path.dropLast(1)
        else { route = if (route == "detail") origin else "home"; path = emptyList(); focusTask = null }
    }
    fun capture() {
        context.startActivity(Intent(context, CaptureActivity::class.java).setAction(
            if (repository.recording.value.phase in listOf("starting","recording","stopping")) ThoughtService.SHOW else ThoughtService.TOGGLE))
    }
    fun present(kind: String, id: String = "") {
        if (kind == "new" || kind == "newForThought") createdTopicID = null
        sheetID = id; sheet = kind
    }
    val consumeFocus by rememberUpdatedState(onFocusConsumed)
    LaunchedEffect(focusID) {
        if (!focusID.isNullOrBlank()) { open(focusID); consumeFocus(focusID) }
    }
    LaunchedEffect(taskDestination) { taskDestination?.let { if (it.claim()) { sheet = null; open(it.thoughtID, it.taskID) } } }
    LaunchedEffect(topics, filter) {
        if (filter !in listOf("all", "none", "pending") && topics.none { it.id == filter }) filter = "all"
    }
    BackHandler(route != "home" && sheet == null) { back() }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
        Column(Modifier.fillMaxSize()) {
        when (route) {
            "detail" -> ThoughtDetailView(path.lastOrNull().orEmpty(), thoughts, topics, statuses, repository, actions,
                focusTask, { back() }, { id -> open(id) }, { present("pick", it) }, { present("link", it) }, onSettings,
                onDeleted = { route = origin; path = emptyList() })
            "topics" -> TopicsEditView(repository, actions, thoughts, topics, { back() },
                onEdit = { present("edit", it.id) }, onNew = { newTopicPrefill = ""; present("new") },
                onMerge = { ids -> mergeIDs = ids; present("merge") })
            "deleted" -> RecentlyDeletedView(deleted, topics, actions, { back() })
            "guide" -> ThoughtButtonGuide({ back() }, onTileSetup, ::capture)
            "search" -> ThoughtsSearchView(thoughts, topics, repository, { back() }, { open(it) },
                onTopic = { filter = it; mapFocus = it; route = "home" }, actions = actions, onTopicPicker = { present("pick", it) })
            else -> {
                if (tasksTab) {
                    TasksPage(thoughts, topics, loaded, actions, onSettings, ::capture, { id, task -> open(id, task) })
                } else {
                    var more by remember { mutableStateOf(false) }
                    val largeType = LocalDensity.current.fontScale >= 1.5f
                    ThoughtToolbar("Gedanken", beta = !largeType, actions = {
                        if (!largeType) IconButton(onClick = { mapMode = !mapMode }) { Glyph(if (mapMode) PaplyIcons.List else PaplyIcons.Map, if (mapMode) "Liste zeigen" else "Karte zeigen", C.greenBright) }
                        IconButton(onClick = { route = "search" }) { Glyph(PaplyIcons.Search, "Suchen", C.greenBright) }
                        Box {
                            IconButton(onClick = { more = true }) { Glyph(PaplyIcons.More, "Mehr", C.greenBright) }
                            DropdownMenu(more, { more = false }) {
                                if (largeType) DropdownMenuItem(text = { Text(if (mapMode) "Liste zeigen" else "Karte zeigen") }, onClick = { more = false; mapMode = !mapMode })
                                DropdownMenuItem(text = { Text("Themen bearbeiten") }, onClick = { more = false; route = "topics" })
                                DropdownMenuItem(text = { Text(if (deleted.isEmpty()) "Zuletzt gelöscht" else "Zuletzt gelöscht (${deleted.size})") }, onClick = { more = false; route = "deleted" })
                            }
                        }
                        IconButton(onClick = onSettings) { Glyph(PaplyIcons.Settings, "Einstellungen", C.greenBright) }
                    })
                    if (error != null) Text(error!!, color = C.beak, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp))
                    if (!loaded) Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = C.thoughtMint) }
                    else if (thoughts.isEmpty()) Box(Modifier.weight(1f)) {
                        ThoughtsEmptyState(setup, { route = "guide" }, ::capture)
                    } else {
                        val chipTopics = topics.filter { topic ->
                            val count = thoughts.count { it.topicId == topic.id }
                            count > 0 && TopicIndex.isActive(topic, count)
                        }
                        if (mapMode) Box(Modifier.weight(1f)) {
                            com.paply.android.ui.thoughts.map.ThoughtMapSlot(thoughts, topics, repository, actions,
                                mapFocus, { mapFocus = it }, { id, task -> open(id, task) }, { present("actions", it) }, setup, setupProgress)
                        } else {
                        val query = listQuery
                        SearchField(query, { listQuery = it }, "Gedanken durchsuchen")
                        val hits by searchResults(repository, query, thoughts, topics)
                        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(vertical = 10.dp)) {
                            item { TopicFilter("Alle", filter == "all", { filter = "all" }) }
                            if (thoughts.any { it.state != ThoughtState.done }) item {
                                TopicFilter("Noch nicht geordnet", filter == "pending", { filter = if (filter == "pending") "all" else "pending" })
                            }
                            if (thoughts.any { it.topicId == null && it.state == ThoughtState.done }) item {
                                TopicFilter("Ohne Thema", filter == "none", { filter = if (filter == "none") "all" else "none" })
                            }
                            items(chipTopics, key = { it.id }) { topic ->
                                TopicFilter(topic.title, filter == topic.id, { filter = if (filter == topic.id) "all" else topic.id }, topic,
                                    onLongClick = { present("actions", topic.id) })
                            }
                        }
                        val shown = if (query.isNotBlank()) hits.mapNotNull { hit -> thoughts.firstOrNull { it.id == hit.thoughtID } }
                            else thoughts.filter { when (filter) { "all" -> true; "none" -> it.topicId == null && it.state == ThoughtState.done
                                "pending" -> it.state != ThoughtState.done; else -> it.topicId == filter } }
                        Box(Modifier.weight(1f)) {
                            ThoughtsList(shown, topics, statuses, filter, actions, { open(it) }, { present("pick", it) },
                                setup = setup, setupProgress = setupProgress, query = query, hits = hits, onEditTopic = { present("actions", it) })
                        }
                        }
                        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("${thoughts.size} ${if (thoughts.size == 1) "Gedanke" else "Gedanken"}" + if (chipTopics.isEmpty()) "" else " · ${chipTopics.size} ${if (chipTopics.size == 1) "Thema" else "Themen"}",
                                color = C.secondary, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                            CaptureButton(::capture)
                        }
                    }
                }
            }
        }
        }
        }
        if (route != "detail") CaptureBar(repository, actions, ::capture) { id -> open(id) }
    }
    val close = { sheet = null }
    when (sheet) {
        "pick" -> TopicPickerSheet(sheetID, topics, thoughts, actions, close,
            onNew = { prefill -> newTopicPrefill = prefill; present("newForThought", sheetID) })
        "new", "newForThought" -> TopicEditor(null, actions, close, prefill = newTopicPrefill) { title, icon, note, image, imageChanged ->
            val assigningID = sheetID.takeIf { sheet == "newForThought" }
            val id = createdTopicID ?: repository.createTopic(title, icon, note).id.also { createdTopicID = it }
            repository.updateTopic(id, title, icon, note)
            if (imageChanged) repository.setTopicImage(id, image)
            if (assigningID != null) repository.setTopic(assigningID, id)
            sheet = null
        }
        "edit" -> topics.firstOrNull { it.id == sheetID }?.let { topic ->
            TopicEditor(topic, actions, close) { title, icon, note, image, imageChanged ->
                repository.updateTopic(topic.id, title, icon, note)
                if (imageChanged) repository.setTopicImage(topic.id, image)
                sheet = null
            }
        }
        "merge" -> TopicMergeSheet(mergeIDs, topics, thoughts, actions, close)
        "link" -> LinkPickerSheet(sheetID, thoughts, topics, repository, actions, close)
        "actions" -> topics.firstOrNull { it.id == sheetID }?.let { topic ->
            TopicActionsSheet(topic, thoughts.count { it.topicId == topic.id }, actions, close,
                onEdit = { present("edit", topic.id) }, onMerge = { mergeIDs = listOf(topic.id); present("merge") })
        }
    }
}

@Composable
private fun TopicFilter(title: String, selected: Boolean, onClick: () -> Unit, topic: Topic? = null, onLongClick: (() -> Unit)? = null) {
    val tint = topicTint(topic?.id)
    Row(Modifier.clip(CircleShape).background(if (selected) C.greenBright else C.row)
        .combinedClickable(onClick = onClick, onLongClick = onLongClick)
        .heightIn(min = 38.dp).padding(horizontal = 14.dp, vertical = 8.dp).semantics { this.selected = selected },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (topic != null) Icon(topic.icon.glyph, null, Modifier.size(15.dp), tint = if (selected) C.forest else tint.ink)
        Text(title, style = MaterialTheme.typography.titleSmall, color = if (selected) C.forest else C.text)
    }
}

/** The list remains available beside the map and for search results. */
@Composable
fun ThoughtsList(thoughts: List<Thought>, topics: List<Topic>, statuses: Map<String, ThoughtsRepository.Status>,
    filter: String, actions: ThoughtsActions, onOpen: (String) -> Unit, onTopicPicker: (String) -> Unit,
    setup: @Composable () -> Unit = {}, setupProgress: Pair<Int, Int> = 0 to 0, query: String = "", hits: List<SearchHit> = emptyList(), onEditTopic: (String) -> Unit = {}) {
    val selectedTopic = topics.firstOrNull { it.id == filter }
    val listState = rememberLazyListState()
    val now by produceState(Instant.now()) { while (true) { value = Instant.now(); delay(30_000) } }
    val groups = thoughts.groupBy { sectionDate(it.createdAt, now) }
    LazyColumn(state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        if (query.isBlank() && filter == "all") item("setup") { ThoughtsHomeHeader(setupProgress.first, setupProgress.second, setup) }
        if (selectedTopic != null && query.isBlank()) item("topic") {
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TopicBadge(selectedTopic, 44.dp)
                Column(Modifier.weight(1f)) {
                    Text(selectedTopic.title, style = MaterialTheme.typography.titleLarge)
                    Text("${thoughts.size} ${if (thoughts.size == 1) "Gedanke" else "Gedanken"}", color = C.secondary, style = MaterialTheme.typography.bodySmall)
                    selectedTopic.describedNote?.let { Text(it, color = C.secondary, style = MaterialTheme.typography.bodySmall) }
                }
                IconButton(onClick = { onEditTopic(selectedTopic.id) }) { Glyph(PaplyIcons.More, "Thema bearbeiten", C.greenBright) }
            }
        }
        val open = if (selectedTopic != null) thoughts.flatMap { thought -> thought.tasks.filter { !it.done }.map { thought to it } } else emptyList()
        if (open.isNotEmpty()) item("topic-tasks") {
            PaplyCard {
                Text("Offen", style = MaterialTheme.typography.titleMedium)
                open.take(3).forEach { (thought, task) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TaskCheck(task, thought.id, actions)
                        TaskText(task, actions, Modifier.weight(1f).clickable { onOpen(thought.id) })
                    }
                }
                if (open.size > 3) Text("Alle ${open.size} zeigen", color = C.greenBright, modifier = Modifier.clickable { onOpen(open[3].first.id) }.padding(8.dp))
            }
        }
        if (thoughts.isEmpty()) item("empty-filter") {
            EmptyState(if (query.isBlank()) "Keine Gedanken" else "Keine Ergebnisse", if (query.isBlank()) "Hier erscheinen die Gedanken zu diesem Thema." else "Keine Treffer für „$query“.", PaplyIcons.Search)
        }
        if (query.isNotBlank() && thoughts.isNotEmpty()) item("count") { ThoughtSectionTitle(if (thoughts.size == 1) "1 Treffer" else "${thoughts.size} Treffer") }
        groups.forEach { (title, members) ->
            if (query.isBlank()) item("section:$title") { ThoughtSectionTitle(title) }
            itemsIndexed(members, key = { _, it -> it.id }) { index, thought ->
                val shape = RoundedCornerShape(topStart = if (index == 0) 14.dp else 0.dp, topEnd = if (index == 0) 14.dp else 0.dp,
                    bottomStart = if (index == members.lastIndex) 14.dp else 0.dp, bottomEnd = if (index == members.lastIndex) 14.dp else 0.dp)
                ThoughtListRow(thought, topics.firstOrNull { it.id == thought.topicId }, statuses[thought.id], actions,
                    onOpen = { onOpen(thought.id) }, onTopic = { onTopicPicker(thought.id) },
                    modifier = Modifier.animateItem(placementSpec = spring(dampingRatio = .73f, stiffness = 420f)).clip(shape), showTopic = selectedTopic == null, query = query,
                    hit = hits.firstOrNull { it.thoughtID == thought.id })
            }
        }
    }
}

@Composable
fun ThoughtsHomeHeader(done: Int, total: Int, setup: @Composable () -> Unit) {
    if (total == 0 || done >= total) return
    var open by rememberSaveable { mutableStateOf(false) }
    Surface(onClick = { open = true }, color = C.row, shape = RoundedCornerShape(18.dp), modifier = Modifier.padding(vertical = 4.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(progress = { done.toFloat() / total }, modifier = Modifier.size(22.dp), color = C.greenBright, trackColor = C.tertiary.copy(alpha=.2f), strokeWidth = 3.dp)
            Column(Modifier.weight(1f)) {
                Text("Einrichten", style = MaterialTheme.typography.titleSmall)
                Text("$done von $total erledigt", style = MaterialTheme.typography.bodySmall, color = C.secondary)
            }
            Glyph(PaplyIcons.Chevron, tint = C.tertiary, size = 14.dp)
        }
    }
    if (open) ThoughtSheet("Einrichten", { open = false }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) { setup() }
    }
}

@Composable
internal fun searchResults(repository: ThoughtsRepository, query: String, thoughts: List<Thought>, topics: List<Topic>): State<List<SearchHit>> {
    // Index once per data change, then search it on a worker thread for every keystroke.
    val index by produceState<com.paply.thoughts.local.ThoughtSearchIndex?>(null, thoughts, topics) {
        try { value = repository.makeSearchIndex() }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { value = null }
    }
    return produceState(emptyList<SearchHit>(), query, index) {
        value = if (query.isBlank()) emptyList() else kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { index?.search(query).orEmpty() }
    }
}

@Composable
private fun ThoughtsSearchView(thoughts: List<Thought>, topics: List<Topic>, repository: ThoughtsRepository,
    onBack: () -> Unit, onOpen: (String) -> Unit, onTopic: (String) -> Unit, actions: ThoughtsActions, onTopicPicker: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val hits by searchResults(repository, query, thoughts, topics)
    val statuses by repository.status.collectAsStateWithLifecycle()
    ThoughtToolbar("Suchen", onBack)
    SearchField(query, { query = it }, "Gedanken durchsuchen")
    if (query.isBlank()) LazyColumn(contentPadding = PaddingValues(16.dp)) {
        item { ThoughtSectionTitle("Themen") }
        items(topics.filter { topic -> thoughts.any { it.topicId == topic.id } }.sortedBy { it.title }, key = { it.id }) { topic ->
            SettingsItem(topic.title, value = thoughts.count { it.topicId == topic.id }.let { if (it == 1) "1 Gedanke" else "$it Gedanken" }, onClick = { onTopic(topic.id) }, trailing = { TopicBadge(topic) })
        }
        item { Text("Sucht in Titel, Text, Rohtext, Aufgaben und Themen – auf dem Gerät, ohne Netz.", style = MaterialTheme.typography.bodySmall, color = C.secondary, modifier = Modifier.padding(16.dp)) }
    } else {
        topics.filter { it.title.contains(query, ignoreCase = true) }.take(3).forEach { topic ->
            TextButton(onClick = { onTopic(topic.id) }, modifier = Modifier.padding(horizontal = 16.dp)) { Text("Thema: ${topic.title}") }
        }
        ThoughtsList(hits.mapNotNull { hit -> thoughts.firstOrNull { it.id == hit.thoughtID } }, topics, statuses, "all", actions, onOpen, onTopicPicker,
            query = query, hits = hits)
    }
}

@Composable
fun CaptureButton(onClick: () -> Unit) {
    FilledIconButton(onClick = onClick, colors = IconButtonDefaults.filledIconButtonColors(containerColor = C.greenBright, contentColor = C.forest), modifier = Modifier.size(48.dp)) {
        PaplyMark(Modifier.size(20.dp, 23.dp).semantics { contentDescription = "Gedanke aufnehmen" }, C.forest)
    }
}
