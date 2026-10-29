@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.paply.android.ui.thoughts

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.model.SearchHit
import java.time.Instant

fun stateMessage(thought: Thought, status: ThoughtsRepository.Status?): String = status?.message?.takeIf { it.isNotBlank() }
    ?: thought.status.message?.takeIf { it.isNotBlank() }
    ?: when (thought.state) {
        ThoughtState.recording -> "Aufnahme läuft"
        ThoughtState.waitingNetwork -> "Gesichert · wartet auf Netz"
        ThoughtState.waitingKey -> "Gesichert · Groq-Schlüssel fehlt"
        ThoughtState.waitingLimit -> "Gesichert · Groq-Limit, später"
        ThoughtState.waitingBudget -> "Gesichert · Kontingent für heute erreicht"
        ThoughtState.needsAttention -> "Ton gesichert · nicht verschriftlicht"
        ThoughtState.done -> if (thought.textIsRaw) "Nicht geordnet · Original-Wortlaut" else "Verarbeitet"
        else -> "Wird geordnet …"
    }

@Composable
fun ThoughtListRow(thought: Thought, topic: Topic?, status: ThoughtsRepository.Status?, actions: ThoughtsActions,
    onOpen: () -> Unit, onTopic: () -> Unit, modifier: Modifier = Modifier, showTopic: Boolean = true,
    query: String = "", hit: SearchHit? = null) {
    var menu by remember { mutableStateOf(false) }
    val raw by produceState<String?>(null, thought.id, thought.rev) {
        if (thought.state != ThoughtState.done && thought.title.isNullOrBlank()) {
            try { value = actions.repository.source(thought.id)?.text }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: Exception) { value = null }
        }
    }
    val title = if (thought.state != ThoughtState.done && thought.title.isNullOrBlank()) raw?.trim()?.take(90)?.takeIf { it.isNotEmpty() } ?: thought.displayTitle else thought.displayTitle
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.StartToEnd -> onTopic()
            SwipeToDismissBoxValue.EndToStart -> actions.trash(thought.id)
            else -> Unit
        }; false
    })
    SwipeToDismissBox(state = swipe, modifier = modifier, backgroundContent = {
        SwipeActionBackground(swipe, "Thema", "Löschen", startColor = C.thoughtSwipe)
    }) {
        Box {
            Column(Modifier.fillMaxWidth().background(C.row).combinedClickable(onClick = onOpen, onLongClick = { menu = true })
                .padding(horizontal = 16.dp, vertical = 12.dp).semantics {
                    customActions = listOf(CustomAccessibilityAction("Thema ändern") { onTopic(); true },
                        CustomAccessibilityAction("Löschen") { actions.trash(thought.id); true },
                        CustomAccessibilityAction("Kopieren") { actions.copy(thought.shareText()); true })
                }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val big = LocalDensity.current.fontScale >= 1.5f
                Text(highlighted(title, query), style = MaterialTheme.typography.titleMedium,
                    maxLines = if (big) 3 else 1, overflow = TextOverflow.Ellipsis)
                if (thought.state == ThoughtState.done) {
                    Text(highlighted(compactDate(thought.createdAt) + "  " + (hit?.snippet ?: thought.previewLine.ifEmpty { "Kein weiterer Text" }), query),
                        style = MaterialTheme.typography.bodyMedium, color = C.secondary,
                        maxLines = if (big) 4 else if (query.isNotBlank()) 2 else 1, overflow = TextOverflow.Ellipsis)
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Glyph(if (thought.state == ThoughtState.needsAttention) PaplyIcons.TriangleAlert else if (thought.state == ThoughtState.waitingNetwork) PaplyIcons.WifiOff else PaplyIcons.Clock,
                            tint = if (thought.state == ThoughtState.needsAttention) C.beak else C.secondary, size = 14.dp)
                        Text(stateMessage(thought, status), style = MaterialTheme.typography.bodyMedium,
                            color = if (thought.state == ThoughtState.needsAttention) C.beak else C.secondary, maxLines = if (big) 3 else 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (showTopic && topic != null) {
                        TopicMark(topic, 13.dp)
                        Text(topic.title, style = MaterialTheme.typography.labelMedium, color = topicTint(topic.id).ink,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, false))
                    }
                    if (thought.textIsRaw) Text("nicht geordnet", style = MaterialTheme.typography.labelSmall,
                        color = C.secondary, modifier = Modifier.background(C.row, RoundedCornerShape(8.dp)).padding(horizontal = 7.dp, vertical = 2.dp))
                    Spacer(Modifier.weight(1f))
                    if (thought.state == ThoughtState.done && !thought.textIsRaw) Glyph(PaplyIcons.Check, "Verarbeitet", C.tertiary, 12.dp)
                    if (thought.openTaskCount > 0) {
                        Glyph(PaplyIcons.Circle, tint = C.secondary, size = 12.dp)
                        Text("${thought.openTaskCount}", style = MaterialTheme.typography.labelMedium, color = C.secondary)
                    }
                    if (thought.links.isNotEmpty()) Glyph(PaplyIcons.Link, "Verknüpft", C.secondary, 13.dp)
                }
                if (thought.state == ThoughtState.needsAttention) TextButton(onClick = { actions.run { actions.repository.retry(thought.id) } },
                    contentPadding = PaddingValues(0.dp)) { Text("Erneut versuchen", style = MaterialTheme.typography.titleSmall) }
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(text = { Text("Teilen") }, onClick = { menu = false; actions.share(thought.shareText()) })
                DropdownMenuItem(text = { Text("Kopieren") }, onClick = { menu = false; actions.copy(thought.shareText()) })
                DropdownMenuItem(text = { Text("Thema ändern") }, onClick = { menu = false; onTopic() })
                if (thought.state == ThoughtState.needsAttention || thought.textIsRaw)
                    DropdownMenuItem(text = { Text("Erneut ordnen") }, onClick = { menu = false; actions.run { actions.repository.reorganize(thought.id) } })
                DropdownMenuItem(text = { Text("Löschen", color = C.danger) }, onClick = { menu = false; actions.trash(thought.id) })
            }
        }
    }
}

/** Card counterpart for the map's later topic panel. Shares the same repository/checkoff actions. */
@Composable
fun ThoughtCard(thought: Thought, actions: ThoughtsActions, onOpen: () -> Unit, raw: String? = null,
    linkCount: Int = thought.links.size, compact: Boolean = false) {
    val parts = if (thought.state != ThoughtState.done && thought.title.isNullOrBlank() && raw != null)
        com.paply.thoughts.display.RawTitle.split(raw) else null
    val open = thought.tasks.filter { !it.done }
    val big = LocalDensity.current.fontScale >= 1.5f
    PaplyCard(Modifier.clickable(onClick = onOpen), radius = 20.dp, color = Color(0xFF1E3F31).copy(alpha = .82f),
        borderColor = Color.White.copy(alpha = .09f), shadow = 6.dp,
        contentPadding = PaddingValues(start = if (compact) 14.dp else 16.dp, end = if (compact) 14.dp else 16.dp, top = 13.dp, bottom = 12.dp)) {
        Text(parts?.title ?: thought.displayTitle, style = MaterialTheme.typography.titleSmall,
            maxLines = if (big) 5 else 2, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        if (parts?.rest?.isNotEmpty() == true) Text(parts.rest, style = MaterialTheme.typography.bodyMedium,
            color = C.secondary, maxLines = if (big) 6 else if (compact) 4 else 2, overflow = TextOverflow.Ellipsis)
        if (thought.state != ThoughtState.done || thought.textIsRaw) Text(stateMessage(thought, null),
            style = MaterialTheme.typography.bodySmall, color = if (thought.state == ThoughtState.needsAttention) C.beak else C.secondary)
        else Text(thought.previewLine, style = if (compact) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
            color = C.secondary, maxLines = if (big) 6 else if (compact) 4 else 2, overflow = TextOverflow.Ellipsis)
        if (thought.state == ThoughtState.done) open.take(2).forEach { task ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                TaskCheck(task, thought.id, actions)
                TaskText(task, actions, Modifier.weight(1f))
            }
        }
        if (open.size > 2) Text("+ ${open.size - 2} weitere", style = MaterialTheme.typography.bodySmall, color = C.secondary, modifier = Modifier.padding(start = 29.dp))
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(compactDate(thought.createdAt), style = MaterialTheme.typography.bodySmall, color = C.tertiary, modifier = Modifier.weight(1f))
            if (linkCount > 0) {
                Glyph(PaplyIcons.Link, tint = C.tertiary, size = 12.dp)
                Text("$linkCount", style = MaterialTheme.typography.bodySmall, color = C.tertiary)
            }
        }
    }
}

@Composable
fun ThoughtStatus(thought: Thought, status: ThoughtsRepository.Status?, actions: ThoughtsActions, onSettings: () -> Unit) {
    val warning = thought.state == ThoughtState.needsAttention
    val text = stateMessage(thought, status)
    if (thought.state == ThoughtState.done && !thought.textIsRaw) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Glyph(PaplyIcons.Check, tint = C.greenBright, size = 14.dp)
            Text("Verarbeitet", style = MaterialTheme.typography.bodySmall, color = C.secondary)
        }
    } else Surface(shape = RoundedCornerShape(14.dp), color = (if (warning) C.beak else C.thoughtMint).copy(alpha=.1f)) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium, color = if (warning) C.beak else C.text,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            status?.audioExpiresAt?.let { expiry ->
                Text("Audio bis zum Rohtext, höchstens bis ${formatDate(expiry,"dd.MM.yyyy")}", style = MaterialTheme.typography.bodySmall, color = C.secondary)
            }
            when {
                thought.state == ThoughtState.waitingKey -> Pill("Eintragen", onSettings)
                warning -> Pill("Erneut versuchen", { actions.run { actions.repository.retry(thought.id) } })
                thought.state == ThoughtState.done && thought.textIsRaw -> Pill("Erneut ordnen", { actions.run { actions.repository.reorganize(thought.id) } })
            }
        }
    }
}
