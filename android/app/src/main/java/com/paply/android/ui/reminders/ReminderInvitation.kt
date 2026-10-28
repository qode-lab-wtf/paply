package com.paply.android.ui.reminders

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.LocalActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.reminders.ReminderPlanning
import com.paply.android.reminders.ReminderState
import com.paply.android.reminders.TaskReminders
import com.paply.android.thoughts.ThoughtsRepository
import com.paply.android.ui.components.*
import com.paply.android.ui.theme.PaplyColors as C
import com.paply.thoughts.Thought
import com.paply.thoughts.ThoughtTask
import com.paply.thoughts.display.TaskReminderPlan
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ReminderActions(val state: ReminderState, val enable: () -> Unit, val disable: () -> Unit,
    val dismiss: () -> Unit, val notificationSettings: () -> Unit, val exactSettings: () -> Unit)

/** Permission requests only follow the invitation or switch; the engine never shows UI. */
@Composable
fun rememberReminderActions(activity: Activity, onError: (String) -> Unit = {}): ReminderActions {
    val reminders = remember(activity) { TaskReminders.get(activity) }
    val state by reminders.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val report by rememberUpdatedState(onError)
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { reminders.requestReconcile() }
    fun run(block: suspend () -> Unit) { scope.launch {
        try { block() } catch (e: CancellationException) { throw e }
        catch (_: Exception) { report("Erinnerungen konnten nicht gespeichert werden. Bitte erneut versuchen.") }
    } }
    fun notifications() {
        activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
    }
    return ReminderActions(state, enable = {
        val askedBefore = state.asked
        run {
            reminders.setEnabled(true)
            if (!reminders.state.value.notificationsAllowed) {
                if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                    (!askedBefore || activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                else notifications()
            }
        }
    }, disable = { run { reminders.setEnabled(false) } }, dismiss = { run { reminders.dismissInvitation() } },
        notificationSettings = { notifications() }, exactSettings = {
            if (Build.VERSION.SDK_INT >= 31) activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                "package:${activity.packageName}".toUri()))
        })
}

@Composable
fun ReminderInvitation(task: ThoughtsRepository.TaskEntry, modifier: Modifier = Modifier, onError: (String) -> Unit = {}) =
    ReminderInvitation(task.task, task.thought, modifier, onError)

/** Embed once in the detail or task list, passing a real repository task. No invitation for day-only/unclear dates. */
@Composable
fun ReminderInvitation(task: ThoughtTask, thought: Thought, modifier: Modifier = Modifier, onError: (String) -> Unit = {}) {
    val activity = LocalActivity.current ?: return
    val actions = rememberReminderActions(activity, onError)
    val now by produceState(Instant.now(), task, thought.id) {
        while (true) { value = Instant.now(); delay(30_000) }
    }
    if (!ReminderPlanning.offersInvitation(TaskReminderPlan.reminderTime(task, thought)?.let { it > now } == true,
            actions.state.beta, actions.state.asked, actions.state.hiddenUntil, now)) return
    PaplyCard(modifier) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Glyph(PaplyIcons.Bell, tint = C.thoughtMint)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("Bei Uhrzeit erinnern?", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Text("Hat eine Aufgabe eine Uhrzeit, meldet sich Paply dann – auch auf dem Sperrbildschirm. Abhaken geht direkt in der Mitteilung. Aufgaben ohne Uhrzeit bleiben still.",
                    style = MaterialTheme.typography.bodyMedium, color = C.secondary)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Pill("Erinnern", actions.enable)
                    Pill("Nicht jetzt", actions.dismiss, prominent = false)
                }
            }
        }
    }
}
