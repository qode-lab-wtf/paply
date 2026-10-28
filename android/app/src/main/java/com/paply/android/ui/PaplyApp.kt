package com.paply.android.ui

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.ThoughtState
import com.paply.android.ThoughtStore
import com.paply.android.history.HistoryEntry
import com.paply.android.history.HistoryStore
import com.paply.android.settings.AppPreferences
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyBackground
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.theme.PaplyTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Public retry hook is the only bridge the later pipeline integration needs for failed entries. */
@Composable
fun PaplyApp(activity: Activity, onRetry: ((HistoryEntry) -> Unit)? = null) {
    PaplyTheme {
        val repository = remember { SettingsRepository.get(activity) }
        val history = remember { HistoryStore.get(activity) }
        val vault = remember { KeyVault(activity) }
        val prefs by repository.state.collectAsStateWithLifecycle()
        val settingsError by repository.error.collectAsStateWithLifecycle()
        val entries by history.entries.collectAsStateWithLifecycle()
        val historyError by history.error.collectAsStateWithLifecycle()
        val thoughtStatus by ThoughtState.current.collectAsStateWithLifecycle()
        var route by rememberSaveable { mutableStateOf("home") }
        var tab by rememberSaveable { mutableStateOf("thoughts") }
        var detailId by rememberSaveable { mutableStateOf<String?>(null) }
        var keyError by remember { mutableStateOf<String?>(null) }
        var hasKey by remember { mutableStateOf(false) }
        var status by remember { mutableStateOf(SetupStatus.read(activity, prefs)) }
        var thoughts by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
        var interrupted by remember { mutableIntStateOf(0) }
        var pending by remember { mutableIntStateOf(0) }
        var diagnostic by remember { mutableStateOf("") }
        val scope = rememberCoroutineScope()
        val snackbar = remember { SnackbarHostState() }
        val screenState = rememberSaveableStateHolder()
        fun message(text: String) { scope.launch { snackbar.showSnackbar(text) } }
        fun refreshKey() {
            try { hasKey = vault.read() != null; keyError = null }
            catch (_: Exception) { hasKey = false; keyError = "Der Schlüssel konnte nicht gelesen werden. Bitte neu sichern." }
        }
        fun refresh() {
            status = SetupStatus.read(activity, repository.state.value)
            refreshKey()
            scope.launch {
                val result = withContext(Dispatchers.IO) {
                    val store = ThoughtStore(activity)
                    Triple(store.entries(), store.interrupted().size, store.pending().size)
                }
                thoughts = result.first; interrupted = result.second; pending = result.third
            }
        }
        fun edit(transform: (AppPreferences) -> AppPreferences) {
            scope.launch {
                try { repository.update(transform) }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { message("Einstellung konnte nicht gespeichert werden. Bitte erneut versuchen.") }
            }
        }
        fun navigate(target: String) { route = target }
        fun back() { route = if (route in listOf("settings", "detail")) "home" else if (route == "diagnostics") "developer" else "settings" }
        fun copy(text: String) {
            if (text.isEmpty()) return
            activity.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Paply", text))
            message("Kopiert")
        }
        fun historyAction(block: suspend () -> Unit) {
            scope.launch {
                try { block() }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { message("Verlauf konnte nicht gespeichert werden. Bitte erneut versuchen.") }
            }
        }
        var microphoneAsked by rememberSaveable { mutableStateOf(false) }
        var notificationAsked by rememberSaveable { mutableStateOf(false) }
        val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { refresh() }
        fun microphone() {
            if (microphoneAsked && !activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) activity.openAppSettings()
            else { microphoneAsked = true; permission.launch(Manifest.permission.RECORD_AUDIO) }
        }
        fun notifications() {
            if (Build.VERSION.SDK_INT >= 33 && (!notificationAsked || activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))) {
                notificationAsked = true; permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
        }
        fun addTile() {
            try { activity.requestThoughtTile { added ->
                if (added) edit { it.copy(tileAdded = true) }
                refresh()
            } } catch (_: Exception) { message("Bitte die Schnelleinstellungen bearbeiten und „Paply-Gedanke“ hinzufügen.") }
        }

        val owner = LocalLifecycleOwner.current
        DisposableEffect(owner) {
            val lifecycleObserver = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) {
                    refresh()
                    scope.launch { try { repository.refreshDetectedLanguages() } catch (_: Exception) { /* repository exposes a read error */ } }
                }
            }
            owner.lifecycle.addObserver(lifecycleObserver)
            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) { override fun onChange(selfChange: Boolean) { refresh() } }
            activity.contentResolver.registerContentObserver(Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD), false, observer)
            activity.contentResolver.registerContentObserver(Settings.Secure.getUriFor(Settings.Secure.ENABLED_INPUT_METHODS), false, observer)
            onDispose { owner.lifecycle.removeObserver(lifecycleObserver); activity.contentResolver.unregisterContentObserver(observer) }
        }
        LaunchedEffect(prefs.betaThoughts) { if (!prefs.betaThoughts) tab = "dictation" }
        LaunchedEffect(prefs.tileAdded, thoughtStatus) { refresh() }
        LaunchedEffect(route) { if (route == "diagnostics") diagnostic = DiagnosticReader.read() }
        BackHandler(route != "home") { back() }

        PaplyBackground {
            Scaffold(containerColor = Color.Transparent,
                snackbarHost = { SnackbarHost(snackbar) { data ->
                    Snackbar(snackbarData = data, containerColor = C.greenBright, contentColor = C.forest)
                } },
                bottomBar = {
                    if (route == "home" && prefs.betaThoughts) NavigationBar(containerColor = C.forestDeep.copy(alpha = 0.96f), tonalElevation = 0.dp) {
                        listOf(Triple("thoughts", "Gedanken", PaplyIcons.MessageCircle), Triple("tasks", "Aufgaben", PaplyIcons.ListChecks), Triple("dictation", "Diktat", PaplyIcons.Globe)).forEach { (id, title, icon) ->
                            NavigationBarItem(selected = tab == id, onClick = { tab = id }, icon = { Glyph(icon, tint = if (tab == id) C.thoughtMint else C.secondary) },
                                label = { Text(title) }, colors = NavigationBarItemDefaults.colors(indicatorColor = C.thoughtMint.copy(alpha = 0.12f),
                                    selectedTextColor = C.thoughtMint, unselectedTextColor = C.secondary))
                        }
                    }
                },
            ) { padding ->
                Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
                    val home = route == "home"
                    val title = when (route) {
                        "home" -> if (!prefs.betaThoughts || tab == "dictation") "Diktat" else if (tab == "tasks") "Aufgaben" else "Gedanken"
                        "settings" -> "Einstellungen"
                        "languages" -> "Sprachen"
                        "vocabulary" -> "Eigene Begriffe"
                        "keyboard" -> "Tastatur einrichten"
                        "tile" -> "Gedanken-Knopf"
                        "developer" -> "Entwicklerbereich"
                        "diagnostics" -> "Diagnose"
                        else -> "Diktat"
                    }
                    PageHeader(title, back = if (home) null else { { back() } }, settings = if (home) { { navigate("settings") } } else null,
                        beta = home && prefs.betaThoughts && tab != "dictation", done = if (home) null else { { navigate("home") } }, large = route != "detail")
                    if (settingsError != null) Text(settingsError!!, color = C.beak, modifier = Modifier.padding(16.dp))
                    Box(Modifier.weight(1f)) {
                        // Preserve each tab/screen's scroll position like the iOS navigation stacks.
                        val screenKey = if (home) "home:$tab" else if (route == "detail") "detail:$detailId" else route
                        screenState.SaveableStateProvider(screenKey) {
                            when (route) {
                                "home" -> {
                                    val setup: @Composable () -> Unit = { SetupCard(prefs, status, hasKey, ::microphone, ::notifications, ::navigate) }
                                    if (!prefs.betaThoughts || tab == "dictation") DictationScreen(entries, status, setup, ::copy,
                                        detail = { detailId = it.id; navigate("detail") }, delete = { entry -> historyAction { history.delete(setOf(entry.id)) } },
                                        deleteAll = { historyAction { history.deleteAll() } }, keyboard = {
                                            if (status.keyboardEnabled && !status.keyboardSelected) activity.chooseKeyboard() else navigate("keyboard")
                                        }, error = historyError, retryLoad = { historyAction { history.reload() } })
                                    else if (tab == "tasks") Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                                        EmptyState("Noch keine Aufgaben", "Aufgaben entstehen aus deinen Gedanken. Sag einfach „Ich muss …“ – Paply hält sie hier fest.", PaplyIcons.ListChecks)
                                    }
                                    else ThoughtsScreen(thoughts, interrupted, pending, thoughtStatus.message, setup) {
                                        scope.launch { withContext(Dispatchers.IO) {
                                            val store = ThoughtStore(activity)
                                            store.interrupted().forEach { store.discard(it) }
                                        }; refresh() }
                                    }
                                }
                                "settings" -> SettingsHome(activity, prefs, vault, hasKey, keyError, status, ::refreshKey, ::edit, ::navigate, ::message)
                                "languages" -> LanguagesScreen(prefs, ::edit)
                                "vocabulary" -> VocabularyScreen(prefs, ::edit)
                                "keyboard" -> KeyboardSetupScreen(activity, status)
                                "tile" -> TileSetupScreen(activity, status, ::addTile)
                                "developer" -> DeveloperScreen(prefs, ::edit, ::navigate)
                                "diagnostics" -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                                    Text("Nur Abläufe, Zeiten und Kennungen – keine Diktate, keine Gedanken.", color = C.secondary, style = MaterialTheme.typography.bodySmall)
                                    TextButton(onClick = { scope.launch { diagnostic = DiagnosticReader.read() } }) { Text("Aktualisieren") }
                                    SelectionContainer { Text(diagnostic.ifEmpty { "Lade Diagnose …" }, style = MaterialTheme.typography.bodySmall) }
                                }
                                "detail" -> HistoryDetailScreen(entries.firstOrNull { it.id == detailId }, ::copy,
                                    share = { shareText(activity, it) }, onRetry = { entry -> onRetry?.invoke(entry)
                                        ?: message("Diese Aufnahme bleibt für einen späteren Neuversuch gesichert.") })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ThoughtsScreen(thoughts: List<JSONObject>, interrupted: Int, pending: Int, status: String,
    setup: @Composable () -> Unit, discardInterrupted: () -> Unit,
) {
    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item("setup") { setup() }
        if (status.isNotEmpty()) item("status") { Text(status, style = MaterialTheme.typography.bodySmall, color = C.secondary) }
        if (thoughts.isEmpty()) item("empty") {
            EmptyState("Deine Gedanken", "Drück den Paply-Knopf in den Schnelleinstellungen und sprich – wie in ein Diktiergerät. Deine Worte bleiben hier festgehalten.", PaplyIcons.Lightbulb)
        }
        itemsIndexed(thoughts) { _, thought ->
            PaplyCard {
                Text(historyDate(thought.getLong("createdAt")), color = C.secondary, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(10.dp))
                SelectionContainer { Text(thought.getString("text"), style = MaterialTheme.typography.bodyLarge) }
            }
        }
        if (pending > 0) item("pending") {
            PaplyCard { Text("$pending Aufnahme(n) warten auf Verarbeitung.", color = C.beak, style = MaterialTheme.typography.bodyMedium) }
        }
        if (interrupted > 0 && !ThoughtState.active) item("interrupted") {
            PaplyCard {
                Text("$interrupted unterbrochene Aufnahme(n), ohne bestätigte Mikrofonprüfung. Werden nicht gesendet.", color = C.secondary, style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = discardInterrupted) { Text("Unterbrochene Aufnahmen löschen", color = C.danger) }
            }
        }
    }
}
