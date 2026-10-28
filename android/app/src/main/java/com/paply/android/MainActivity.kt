package com.paply.android

import android.graphics.Color
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.paply.android.ui.PaplyApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A notification can recreate an existing task after process death, with saved state present.
        openReminder(intent)
        // The iOS reference deliberately uses its dark forest appearance in both system themes.
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT))
        setContent { PaplyApp(this, onRetry = { com.paply.android.dictation.DictationRuntime.retry(applicationContext, it) }) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openReminder(intent)
    }

    private fun openReminder(intent: Intent?) {
        com.paply.android.reminders.ReminderLinks.parse(intent)?.let {
            com.paply.android.thoughts.ThoughtsRepository.get(applicationContext).openTaskFromReminder(it)
        }
    }
}
