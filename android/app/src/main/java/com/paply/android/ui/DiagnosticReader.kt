package com.paply.android.ui

import android.app.Activity
import android.content.Intent
import android.os.Build
import com.paply.android.Diag
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Only the sanitized in-memory buffer is exported, identically in debug and release. */
object DiagnosticReader {
    suspend fun read(): String = withContext(Dispatchers.IO) {
        Diag.event("diagnostics.export")
        val safe = Diag.events().takeLast(200)
        "Paply $VERSION\nAndroid ${Build.VERSION.RELEASE} · API ${Build.VERSION.SDK_INT}\nNur Abläufe und Messwerte, keine Inhalte.\n\n" +
            safe.joinToString("\n").ifBlank { "Keine Diagnose-Ereignisse vorhanden." }
    }
}

fun shareText(activity: Activity, text: String, title: String = "Teilen") {
    activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, title)
        putExtra(Intent.EXTRA_TEXT, text)
    }, title))
}
