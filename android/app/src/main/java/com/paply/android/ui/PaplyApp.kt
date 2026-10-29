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
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.thoughts.Thought
import com.paply.thoughts.ThoughtState as StoredThoughtState
import com.paply.android.history.HistoryEntry
import com.paply.android.history.HistoryStore
import com.paply.android.settings.AppPreferences
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.thoughts.*
import com.paply.android.ui.theme.PaplyBackground
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.android.ui.theme.PaplyTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


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
        var setupReturnRoute by rememberSaveable { mutableStateOf("home") }
        var tab by rememberSaveable { mutableStateOf("thoughts") }
        var detailId by rememberSaveable { mutableStateOf<String?>(null) }
        var keyError by remember { mutableStateOf<String?>(null) }
        var hasKey by remember { mutableStateOf(false) }
        var status by remember { mutableStateOf(SetupStatus.read(activity, prefs)) }
        val thoughtRepository = remember { ThoughtsRepository.get(activity) }
        var taskDestination by remember { mutableStateOf<com.paply.android.ui.tasks.TaskOpenRequest?>(null) }
        com.paply.android.ui.reminders.ReminderDeepLinkEffect(thoughtRepository) { thoughtID, taskID ->
            if (prefs.betaThoughts) {
                taskDestination = com.paply.android.ui.tasks.TaskOpenRequest(thoughtID, taskID)
                tab = "tasks"; route = "home"
            } else { route = "settings" }
        }
        var diagnostic by remember { mutableStateOf("") }
        val scope = rememberCoroutineScope()
        val snackbar = remember { SnackbarHostState() }
        val thoughtActions = remember(thoughtRepository, scope, snackbar) { ThoughtsActions(thoughtRepository, activity.applicationContext, scope, snackbar) }
        val screenState = rememberSaveableStateHolder()
        fun message(text: String) { scope.launch { snackbar.showSnackbar(text) } }
        fun refreshKey() {
            scope.launch {
                try { hasKey = withContext(Dispatchers.IO) { vault.read() != null }; keyError = null }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { hasKey = false; keyError = "Der Schlüssel konnte nicht gelesen werden. Bitte neu sichern." }
            }
        }
        fun refresh() {
            status = SetupStatus.read(activity, repository.state.value)
            thoughtRepository.kick("foreground")
        }
        fun edit(transform: (AppPreferences) -> AppPreferences) {
            scope.launch {
                try { repository.update(transform) }
                catch (e: CancellationException) { throw e }
                catch (_: Exception) { message("Einstellung konnte nicht gespeichert werden. Bitte erneut versuchen.") }
            }
        }
        fun navigate(target: String) {
            if (target in listOf("keyboard", "tile")) setupReturnRoute = route
            route = target
        }
        fun back() { route = if (route in listOf("keyboard", "tile")) setupReturnRoute else if (route in listOf("settings", "detail")) "home" else if (route == "diagnostics") "developer" else "settings" }
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
        val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { refresh() }
        fun microphone() {
            if (status.microphoneDenied) activity.openAppSettings()
            else { markPermissionAsked(activity, Manifest.permission.RECORD_AUDIO); permission.launch(Manifest.permission.RECORD_AUDIO) }
        }
        fun notifications() {
            if (Build.VERSION.SDK_INT >= 33 && !status.notificationsDenied) {
                markPermissionAsked(activity, Manifest.permission.POST_NOTIFICATIONS); permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else activity.openAppSettings()
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
        LaunchedEffect(vault) { refreshKey() }
        LaunchedEffect(prefs.betaThoughts) { if (!prefs.betaThoughts) tab = "dictation" }
        LaunchedEffect(prefs.tileAdded, thoughtStatus.phase, thoughtStatus.id, thoughtStatus.message) { refresh() }
        LaunchedEffect(route) { if (route == "diagnostics") diagnostic = DiagnosticReader.read() }
        BackHandler(route != "home") { back() }

        TopicAppearanceProvider(thoughtRepository, thoughtActions.appearanceRevision) {
        PaplyBackground {
            Scaffold(containerColor = Color.Transparent,
                snackbarHost = { SnackbarHost(snackbar) { data ->
                    Snackbar(snackbarData = data, containerColor = C.greenBright, contentColor = C.forest)
                } },
                bottomBar = {
                    if (route == "home" && prefs.betaThoughts) NavigationBar(containerColor = C.forestDeep.copy(alpha = 0.96f), tonalElevation = 0.dp) {
                        listOf(Triple("thoughts", "Gedanken", PaplyIcons.MessageCircle), Triple("tasks", "Aufgaben", PaplyIcons.ListChecks), Triple("dictation", "Diktat", PaplyIcons.Globe)).forEach { (id, title, icon) ->
                            NavigationBarItem(selected = tab == id, onClick = { tab = id }, icon = { if (id == "tasks") ThoughtsTaskTabIcon(thoughtRepository, tab == id) else Glyph(icon, tint = if (tab == id) C.thoughtMint else C.secondary) },
                                label = { Text(title) }, colors = NavigationBarItemDefaults.colors(indicatorColor = C.thoughtMint.copy(alpha = 0.12f),
                                    selectedTextColor = C.thoughtMint, unselectedTextColor = C.secondary))
                        }
                    }
                },
            ) { padding ->
                Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()) {
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
                    if (!(home && prefs.betaThoughts && tab != "dictation")) PageHeader(title, back = if (home) null else { { back() } }, settings = if (home) { { navigate("settings") } } else null,
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
                                            navigate("keyboard")
                                        }, error = historyError, retryLoad = { historyAction { history.reload() } })
                                    else ThoughtsTab(thoughtRepository, thoughtActions, tasksTab = tab == "tasks", setup = setup,
                                        onSettings = { navigate("settings") }, onTileSetup = { navigate("tile") },
                                        taskDestination = taskDestination.takeIf { tab == "tasks" },
                                        focusID = activity.intent.getStringExtra("thoughtId").takeIf { tab == "thoughts" },
                                        onFocusConsumed = { consumeThoughtLink(activity.intent, it) },
                                        setupProgress = listOf(status.microphone, status.notifications, hasKey, status.keyboardEnabled, status.keyboardTried, status.tileAdded).count { it } to 6)
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
}

/** Consume only the link actually opened; a newer notification must remain pending. */
internal fun consumeThoughtLink(intent: Intent, openedID: String) {
    if (intent.getStringExtra("thoughtId") == openedID) intent.removeExtra("thoughtId")
}
