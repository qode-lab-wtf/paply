package com.paply.android

import android.app.Application

class PaplyApplication : Application() {
    override fun attachBaseContext(base: android.content.Context) {
        super.attachBaseContext(base)
        if (!getProcessName().endsWith(":recovery")) StartupFailure.install(this)
    }

    override fun onCreate() {
        super.onCreate()
        if (getProcessName().endsWith(":recovery") || StartupFailure.pending(this) != null) return
        try {
        com.paply.android.thoughts.ThoughtsRepository.get(this)
        com.paply.android.thoughts.ThoughtNotifications.channels(this)
        com.paply.android.dictation.DictationRuntime.recover(this)
        // Remove only obsolete Phase-0 cache recordings. Confirmed dictations now live in
        // files/dictations and are recovered above; thoughts have their own durable store.
        cacheDir.listFiles()?.filter { it.name.startsWith("dictation-") && it.extension == "wav" }
            ?.forEach { it.delete() }
        } catch (error: Throwable) {
            StartupFailure.record(this, error)
        }
    }
}
