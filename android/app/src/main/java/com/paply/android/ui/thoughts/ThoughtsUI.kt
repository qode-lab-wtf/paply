package com.paply.android.ui.thoughts

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.*
import com.paply.thoughts.display.TaskDueLabel
import com.paply.thoughts.local.ThoughtSearch
import kotlinx.coroutines.*
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale

/** One controller above the tab stacks: pending checkoffs survive tab changes. */
@Stable
class ThoughtsActions(val repository: ThoughtsRepository, private val context: Context,
    private val scope: CoroutineScope, private val snackbar: SnackbarHostState) {
    val pending = mutableStateMapOf<String, Boolean>()
    private val timers = mutableMapOf<String, Job>()
    var appearanceRevision by mutableIntStateOf(0)
        private set
    fun run(success: String? = null, action: suspend () -> Unit) {
        scope.launch {
            try { action(); appearanceRevision++; if (success != null) message(success) }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { message("Änderung konnte nicht gespeichert werden. Bitte erneut versuchen.") }
        }
    }
    fun message(text: String) { scope.launch { snackbar.showSnackbar(text) } }
    fun withUndo(text: String, seconds: Long = 4, action: suspend () -> (suspend () -> Unit)) {
        run {
            val undo = action()
            appearanceRevision++
            snackbar.currentSnackbarData?.dismiss()
            val result = withTimeoutOrNull(seconds * 1000) {
                snackbar.showSnackbar(text, "Widerrufen", duration = SnackbarDuration.Indefinite)
            }
            if (result == SnackbarResult.ActionPerformed) { undo(); appearanceRevision++ }
        }
    }
    fun trash(id: String, after: () -> Unit = {}) = withUndo("Gelöscht") {
        repository.trash(id); after(); suspend { repository.restore(id) }
    }
    fun deleteTask(thoughtID: String, taskID: String) = withUndo("Aufgabe gelöscht") {
        timers.remove(taskID)?.cancel(); pending.remove(taskID)
        repository.deleteTask(thoughtID, taskID)
    }
    fun toggle(thoughtID: String, task: ThoughtTask) {
        val current = repository.thoughts.value.firstOrNull { it.id == thoughtID }?.tasks?.firstOrNull { it.id == task.id } ?: return
        if (timers.containsKey(task.id)) {
            val running = timers.remove(task.id)
            running?.cancel(); pending.remove(task.id)
            run { running?.join(); repository.setTaskDone(thoughtID, task.id, false) }
        } else if (current.done) run { repository.setTaskDone(thoughtID, task.id, false) }
        else {
            pending[task.id] = true
            timers[task.id] = scope.launch {
                try {
                    delay(1200)
                    val thought = repository.thought(thoughtID)
                    if (thought?.deletedAt == null && thought?.tasks?.any { it.id == task.id && !it.done } == true)
                        repository.setTaskDone(thoughtID, task.id, true)
                } catch (e: CancellationException) { throw e }
                catch (_: Exception) { message("Aufgabe konnte nicht gespeichert werden. Bitte erneut versuchen.") }
                finally {
                    if (timers[task.id] === currentCoroutineContext().job) {
                        pending.remove(task.id); timers.remove(task.id)
                    }
                }
            }
        }
    }
    fun copy(text: String) {
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Paply", text))
        message("Kopiert")
    }
    fun share(text: String) {
        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text)
        }, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

data class TopicAppearance(val slots: Map<String, Int> = emptyMap(), val images: Map<String, Bitmap> = emptyMap())
val LocalTopicAppearance = staticCompositionLocalOf { TopicAppearance() }

@Composable
fun TopicAppearanceProvider(repository: ThoughtsRepository, revision: Int, content: @Composable () -> Unit) {
    val topics by repository.topics.collectAsState()
    val deleted by repository.deleted.collectAsState()
    val appearance by produceState(TopicAppearance(), topics, deleted, revision) {
        try {
            value = withContext(Dispatchers.IO) {
                TopicAppearance(repository.topicColorSlots(), repository.topicImages().mapNotNull { (id, bytes) ->
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { id to it }
                }.toMap())
            }
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { /* Symbols remain available; never replace unreadable color files. */ }
    }
    CompositionLocalProvider(LocalTopicAppearance provides appearance, content = content)
}

private data class PaletteEntry(val hue: Float, val saturation: Float, val ink: Float)
private val palette = listOf(PaletteEntry(214f,.72f,.79f), PaletteEntry(240f,.56f,.84f),
    PaletteEntry(272f,.48f,.82f), PaletteEntry(334f,.58f,.81f), PaletteEntry(6f,.72f,.81f),
    PaletteEntry(28f,.86f,.75f), PaletteEntry(44f,.84f,.75f), PaletteEntry(164f,.50f,.75f),
    PaletteEntry(192f,.64f,.75f), PaletteEntry(26f,.34f,.77f))
data class TopicTint(val ink: Color, val base: Color, val badge: Color, val stroke: Color)
@Composable
fun topicTint(id: String?): TopicTint {
    val slot = LocalTopicAppearance.current.slots[id]
    val entry = if (id.isNullOrEmpty() || id.startsWith("_")) PaletteEntry(150f,.08f,.76f)
        else palette[slot?.takeIf { it in palette.indices } ?: preferredSlot(id)]
    fun color(light: Float, alpha: Float = 1f): Color {
        val bright = light + entry.saturation * minOf(light, 1f-light)
        val sat = if (bright == 0f) 0f else 2f * (1f-light/bright)
        return Color.hsv(entry.hue, sat, bright, alpha)
    }
    return TopicTint(color(entry.ink), color(.6f), color(.6f,.22f), color(.7f,.16f))
}
private fun preferredSlot(id: String): Int {
    var hash = 0xCBF29CE484222325uL
    id.toByteArray().forEach { hash = (hash xor it.toUByte().toULong()) * 0x100000001B3uL }
    return (hash % 10uL).toInt()
}

val TopicIcon.glyph: ImageVector get() = when(this) {
    TopicIcon.sparkles -> PaplyIcons.Sparkles; TopicIcon.lightbulb -> PaplyIcons.Lightbulb
    TopicIcon.home -> PaplyIcons.House; TopicIcon.code -> PaplyIcons.CodeXml
    TopicIcon.mapPin -> PaplyIcons.MapPin; TopicIcon.sun -> PaplyIcons.Sun; TopicIcon.moon -> PaplyIcons.Moon
    TopicIcon.heart -> PaplyIcons.Heart; TopicIcon.coffee -> PaplyIcons.Coffee
    TopicIcon.briefcase -> PaplyIcons.BriefcaseBusiness; TopicIcon.calendar -> PaplyIcons.CalendarDays
    TopicIcon.messageCircle -> PaplyIcons.MessageCircle; TopicIcon.book -> PaplyIcons.BookOpen
    TopicIcon.music -> PaplyIcons.Music; TopicIcon.camera -> PaplyIcons.Camera; TopicIcon.leaf -> PaplyIcons.Leaf
    TopicIcon.flag -> PaplyIcons.Flag; TopicIcon.circleHelp -> PaplyIcons.CircleQuestionMark
    TopicIcon.pencil -> PaplyIcons.Pencil; TopicIcon.plane -> PaplyIcons.Plane; TopicIcon.wallet -> PaplyIcons.Wallet
    TopicIcon.users -> PaplyIcons.Users; TopicIcon.list -> PaplyIcons.List; TopicIcon.zap -> PaplyIcons.Zap
}
val TopicIcon.spokenName: String get() = listOf("Funken", "Glühbirne", "Haus", "Code", "Ort", "Sonne", "Mond", "Herz", "Kaffee", "Aktentasche", "Kalender", "Sprechblase", "Buch", "Musik", "Kamera", "Blatt", "Flagge", "Fragezeichen", "Stift", "Flugzeug", "Karte", "Personen", "Liste", "Blitz")[ordinal]

@Composable
fun TopicBadge(topic: Topic?, size: Dp = 30.dp, gradient: Boolean = false) {
    val image = LocalTopicAppearance.current.images[topic?.id]
    val tint = topicTint(topic?.id)
    val shape = RoundedCornerShape(size * .3f)
    if (image != null) Image(image.asImageBitmap(), null, Modifier.size(size).clip(shape).border(1.dp, tint.base, shape))
    else Box(Modifier.size(size).then(if (gradient) Modifier.background(C.thoughtFill, shape) else Modifier.background(tint.badge, shape)), contentAlignment = Alignment.Center) {
        Icon(topic?.icon?.glyph ?: PaplyIcons.CircleDashed, null, Modifier.size(size * .54f), tint = if (gradient) C.forest else tint.ink)
    }
}

@Composable
fun TopicMark(topic: Topic, size: Dp = 15.dp) {
    val image = LocalTopicAppearance.current.images[topic.id]
    if (image != null) Image(image.asImageBitmap(), null, Modifier.size(size * 1.4f).clip(CircleShape))
    else Icon(topic.icon.glyph, null, Modifier.size(size), tint = topicTint(topic.id).ink)
}

@Composable
fun TopicPill(topic: Topic?, onClick: () -> Unit) {
    val tint = topicTint(topic?.id)
    Surface(onClick = onClick, shape = CircleShape, color = if (topic == null) C.row else tint.badge,
        border = BorderStroke(.5.dp, if (topic == null) C.tertiary.copy(alpha=.2f) else tint.stroke)) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (topic != null) TopicMark(topic, 15.dp) else Glyph(PaplyIcons.Tag, tint = C.secondary, size = 15.dp)
            Text(topic?.title ?: "Thema wählen", style = MaterialTheme.typography.titleSmall, color = if (topic == null) C.secondary else tint.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 220.dp))
            Text("⌄", color = tint.ink)
        }
    }
}

@Composable
fun ThoughtSectionTitle(title: String, count: Int? = null, tint: Color = C.text) {
    Row(Modifier.padding(top = 14.dp, bottom = 4.dp).semantics { heading() }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = tint)
        if (count != null) Text("$count", style = MaterialTheme.typography.titleLarge, color = C.tertiary)
    }
}

@Composable
fun ThoughtToolbar(title: String, back: (() -> Unit)? = null, beta: Boolean = false, large: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
            if (back != null) IconButton(onClick = back) { Glyph(PaplyIcons.Back, "Zurück", C.greenBright) }
            else if (beta) BetaBadge()
            if (!large) Text(title, style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f).padding(start = if (beta) 12.dp else 0.dp).semantics { heading() })
            else Spacer(Modifier.weight(1f))
            actions()
        }
        if (large) Text(title, style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(bottom = 12.dp).semantics { heading() })
    }
}

@Composable
fun SearchField(value: String, onChange: (String) -> Unit, placeholder: String) {
    OutlinedTextField(value, onChange, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        singleLine = true, shape = RoundedCornerShape(12.dp), textStyle = MaterialTheme.typography.bodyMedium,
        placeholder = { Text(placeholder, color = C.tertiary) },
        leadingIcon = { Glyph(PaplyIcons.Search, tint = C.tertiary, size = 18.dp) },
        trailingIcon = { if (value.isNotEmpty()) IconButton(onClick = { onChange("") }) { Glyph(PaplyIcons.Close, "Suche löschen", C.secondary, 18.dp) } },
        colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = C.row, focusedContainerColor = C.row,
            unfocusedBorderColor = Color.Transparent, focusedBorderColor = C.greenBright))
}

@Composable
fun TaskCheck(task: ThoughtTask, thoughtID: String, actions: ThoughtsActions) {
    val done = task.done || actions.pending[task.id] == true
    val haptic = LocalHapticFeedback.current
    val scale by animateFloatAsState(if (done) 1f else .95f, spring(dampingRatio = .53f, stiffness = 520f), label = "task-check")
    IconButton(onClick = { haptic.performHapticFeedback(HapticFeedbackType.ToggleOn); actions.toggle(thoughtID, task) },
        modifier = Modifier.semantics { contentDescription = (if (done) "Erledigt: " else "Abhaken: ") + task.text; stateDescription = if (done) "erledigt" else "offen" }) {
        Box(Modifier.size(22.dp * scale).background(if (done) C.greenBright else Color.Transparent, CircleShape)
            .border(1.6.dp, if (done) Color.Transparent else C.tertiary, CircleShape), contentAlignment = Alignment.Center) {
            if (done) Icon(PaplyIcons.Check, null, Modifier.size(14.dp), tint = C.forest)
        }
        // The icon itself is decorative; the button carries a complete action label.
    }
}

@Composable
fun TaskText(task: ThoughtTask, actions: ThoughtsActions, modifier: Modifier = Modifier) {
    val done = task.done || actions.pending[task.id] == true
    Text(task.text, modifier = modifier, style = MaterialTheme.typography.bodyLarge,
        color = if (done) C.secondary else C.text, textDecoration = if (done) TextDecoration.LineThrough else null)
}

val Thought.displayTitle: String get() = title?.takeIf { it.isNotBlank() } ?: if (state == ThoughtState.done) "Ohne Titel"
    else if (durationMs > 0) "Gedanke · ${clock(durationMs / 1000L)}" else "Gedanke"
val Thought.previewLine: String get() = text.orEmpty().take(160).replace('\n', ' ').trim()
val Thought.openTaskCount: Int get() = tasks.count { !it.done }
fun Thought.shareText(): String = listOfNotNull(displayTitle, text?.takeIf { it.isNotBlank() },
    tasks.takeIf { it.isNotEmpty() }?.joinToString("\n", prefix = "Aufgaben:\n") { (if (it.done) "☑ " else "☐ ") + it.text }).joinToString("\n\n")
fun clock(seconds: Long): String = "${seconds.coerceAtLeast(0) / 60}:${(seconds.coerceAtLeast(0) % 60).toString().padStart(2,'0')}"
fun formatDate(instant: Instant, pattern: String): String = DateTimeFormatter.ofPattern(pattern, Locale.GERMAN).withZone(ZoneId.systemDefault()).format(instant)
fun dateLine(thought: Thought): String = formatDate(thought.createdAt, "EEE, d. MMM · HH:mm") +
    if (thought.durationMs <= 0) "" else " · " + if (thought.durationMs < 60_000) "${thought.durationMs / 1000} Sek." else "${clock(thought.durationMs / 1000L)} Min."
fun compactDate(at: Instant, now: Instant = Instant.now()): String {
    val date = at.atZone(ZoneId.systemDefault()).toLocalDate()
    val today = now.atZone(ZoneId.systemDefault()).toLocalDate()
    return when { date == today -> formatDate(at,"HH:mm"); date == today.minusDays(1) -> "Gestern"
        date > today.minusDays(7) -> formatDate(at,"EEEE")
        else -> formatDate(at, if (date.year == today.year) "dd.MM." else "dd.MM.yy") }
}
fun sectionDate(at: Instant, now: Instant = Instant.now()): String {
    val date = at.atZone(ZoneId.systemDefault()).toLocalDate(); val today = now.atZone(ZoneId.systemDefault()).toLocalDate()
    return when { date >= today -> "Heute"; date == today.minusDays(1) -> "Gestern"; date > today.minusDays(7) -> "Vorherige 7 Tage"
        date > today.minusDays(30) -> "Vorherige 30 Tage"; else -> formatDate(at, if (date.year == today.year) "MMMM" else "MMMM yyyy") }
}
fun dueText(task: ThoughtTask, thought: Thought, now: Instant): String? {
    fun time(at: Instant?) = at?.let { " · " + formatDate(it,"HH:mm") }.orEmpty()
    return when (val label = TaskDueLabel.make(task, thought.createdAt, now)) {
        is TaskDueLabel.Wording -> label.text; is TaskDueLabel.Today -> "Heute" + time(label.time)
        is TaskDueLabel.Tomorrow -> "Morgen" + time(label.time); is TaskDueLabel.Yesterday -> "Gestern" + time(label.time)
        is TaskDueLabel.Weekday -> formatDate(label.date,"EEEE") + time(label.time)
        is TaskDueLabel.Date -> formatDate(label.date,"d. MMM") + time(label.time); null -> null
    }
}
fun highlighted(text: String, query: String): AnnotatedString = buildAnnotatedString {
    append(text)
    val tokens = ThoughtSearch.tokens(query)
    Regex("[\\p{L}\\p{N}]+").findAll(text).forEach { match ->
        if (tokens.any { ThoughtSearch.fold(match.value).startsWith(it) })
            addStyle(SpanStyle(color = C.thoughtMint, fontWeight = FontWeight.Bold), match.range.first, match.range.last + 1)
    }
}

/** Draw actions only in the exposed strip. Rows are translucent over the forest background. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwipeActionBackground(state: SwipeToDismissBoxState, startLabel: String, endLabel: String,
    startColor: Color = C.green, endColor: Color = C.danger) {
    val offset = runCatching { state.requireOffset() }.getOrDefault(0f)
    val exposed = with(LocalDensity.current) { kotlin.math.abs(offset).toDp() }
    val starting = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
    Box(Modifier.fillMaxSize()) {
        if (exposed > 0.dp) Box(Modifier.fillMaxHeight().width(exposed)
            .align(if (offset > 0) Alignment.CenterStart else Alignment.CenterEnd)
            .clip(androidx.compose.ui.graphics.RectangleShape).background(if (starting) startColor else endColor)
            .padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
            Text(if (starting) startLabel else endLabel, color = C.text, style = MaterialTheme.typography.titleSmall,
                maxLines = 1, softWrap = false)
        }
    }
}
