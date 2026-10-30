package com.paply.android.ui.reminders

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.paply.android.thoughts.ThoughtsRepository

/** UI-owned navigation callback. MainActivity preserves a cold-start request until the repository is loaded. */
@Composable
fun ReminderDeepLinkEffect(repository: ThoughtsRepository, onOpen: (thoughtID: String, taskID: String) -> Unit) {
    val activity = LocalActivity.current
    val destination by repository.reminderDestination.collectAsStateWithLifecycle()
    val loaded by repository.isLoaded.collectAsStateWithLifecycle()
    val open by rememberUpdatedState(onOpen)
    LaunchedEffect(destination, loaded) {
        val target = destination ?: return@LaunchedEffect
        if (loaded) {
            open(target.thoughtID, target.taskID)
            repository.consumeReminderDestination(target)
            // Once navigation succeeded, rotation must not replay the original notification intent.
            if (com.paply.android.reminders.ReminderLinks.parse(activity?.intent) == target) activity?.intent?.data = null
        }
    }
}
