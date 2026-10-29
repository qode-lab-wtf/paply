package com.paply.android

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.util.Collections
import java.util.IdentityHashMap

/** Never include Throwable.message/toString: these may contain transcripts, paths or credentials. */
internal fun safeStackTrace(error: Throwable): String = buildString {
    val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
    var current: Throwable? = error
    while (current != null && seen.add(current) && seen.size <= 8) {
        appendLine(current.javaClass.name)
        current.stackTrace.take(48).forEach {
            appendLine("  at ${it.className}.${it.methodName}(${it.fileName}:${it.lineNumber})")
        }
        current = current.cause
        if (current != null) append("Caused by: ")
    }
}.take(24000)

internal object StartupFailure {
    @Volatile var report: String? = null
    private fun file(context: Context) = File(context.noBackupFilesDir, "startup-failure.txt")
    fun pending(context: Context): String? = report ?: runCatching {
        file(context).takeIf { it.isFile }?.inputStream()?.bufferedReader()?.use { it.readText().take(26000) }
    }.getOrNull()
    fun record(context: Context, error: Throwable) {
        report = "Paply ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\n" +
            "${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE}; API ${Build.VERSION.SDK_INT}\n" +
            safeStackTrace(error)
        runCatching { file(context).writeText(report!!) }
    }
    fun open(context: Context) {
        context.startActivity(Intent(context, StartupFailureActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
    }
    fun install(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val handling = java.util.concurrent.atomic.AtomicBoolean()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            if (handling.compareAndSet(false, true)) {
                runCatching { record(context, error); open(context) }
            }
            // Never resume a failed main looper or coroutine. Recovery has its own minimal process.
            previous?.uncaughtException(thread, error)
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }
    fun clear(context: Context) { file(context).delete(); report = null }
}

/** No Compose, repositories, WorkManager or Keystore in this process. */
class StartupFailureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = StartupFailure.pending(this) ?: "Paply: Fehlerbericht nicht verfügbar."
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
            addView(TextView(context).apply { text = "Paply konnte nicht gestartet werden"; textSize = 24f })
            addView(TextView(context).apply { text = "Deine Daten bleiben erhalten. Der Bericht enthält nur technische Stackframes und Geräteangaben." })
            addView(Button(context).apply {
                text = "Fehlerbericht teilen"
                setOnClickListener {
                    startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"; putExtra(Intent.EXTRA_TEXT, report)
                    }, "Fehlerbericht teilen"))
                }
            })
            addView(Button(context).apply {
                text = "Erneut versuchen"
                setOnClickListener {
                    getSystemService(android.app.ActivityManager::class.java).runningAppProcesses
                        ?.filter { it.processName == packageName }
                        ?.forEach { android.os.Process.killProcess(it.pid) }
                    StartupFailure.clear(context)
                    startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
                    finish()
                }
            })
            addView(TextView(context).apply { text = report; textSize = 12f })
        }
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
