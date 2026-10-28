package com.paply.android.ui

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Process
import com.paply.android.Diag
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Reads the existing Diag tag. Only fixed events + numeric/boolean measurements leave this app. */
object DiagnosticReader {
    suspend fun read(): String = withContext(Dispatchers.IO) {
        Diag.event("diagnostics.export")
        val log = runCatching {
            val process = ProcessBuilder("logcat", "-d", "-t", "500", "--pid=${Process.myPid()}", "-v", "raw", "Paply:D", "*:S")
                .redirectErrorStream(false).start()
            try { process.inputStream.bufferedReader().use { it.readText() } } finally { process.destroy() }
        }.getOrDefault("")
        val safe = log.lineSequence().mapNotNull { line ->
            val event = Regex("^([a-z][A-Za-z0-9]*(?:\\.[A-Za-z][A-Za-z0-9]*)+)(?:\\s|$)").find(line)?.groupValues?.get(1) ?: return@mapNotNull null
            val measurements = Regex("\\b(ms|chars|len|bytes|chunks|voiced|present|on|active|silenced|audioDeleted|fileDeleted|result)=([A-Za-z0-9.\\-]+)")
                .findAll(line).mapNotNull { match ->
                    val value = match.groupValues[2]
                    if (value.toDoubleOrNull()?.isFinite() == true || value in listOf("true", "false", "valid", "invalid", "offline", "failed")) match.value else null
                }.joinToString(" ")
            event + if (measurements.isEmpty()) "" else " $measurements"
        }.take(200).toList()
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
