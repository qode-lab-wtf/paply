package com.paply.android.ui

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.paply.android.button.PaplyButtonService
import kotlinx.coroutines.delay

internal fun buttonSetupLocation(manufacturer: String): String =
    if (manufacturer.equals("samsung", ignoreCase = true)) {
        "Dort: Installierte Apps → Paply → einschalten."
    } else {
        "Dort: Heruntergeladene Apps (oder Installierte Apps) → Paply → einschalten."
    }

internal fun Context.openButtonAccessibilitySettings() {
    val component = ComponentName(this, PaplyButtonService::class.java).flattenToString()
    val key = ":settings:fragment_args_key"
    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        .putExtra(key, component)
        .putExtra(":settings:show_fragment_args", Bundle().apply { putString(key, component) })
    try {
        startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}

/** Keep polling for changes in Settings; refresh immediately when Paply resumes. */
@Composable
internal fun rememberButtonServiceEnabled(onResume: (Boolean) -> Unit = {}): Boolean {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val currentOnResume by rememberUpdatedState(onResume)
    fun read() = context.getSystemService(AccessibilityManager::class.java)
        .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        .any { ComponentName.unflattenFromString(it.id) == ComponentName(context, PaplyButtonService::class.java) }
    var enabled by remember(context) { mutableStateOf(read()) }
    LaunchedEffect(context) {
        while (true) {
            enabled = read()
            delay(500)
        }
    }
    DisposableEffect(owner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                enabled = read()
                currentOnResume(enabled)
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    return enabled
}
