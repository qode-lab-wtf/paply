package com.paply.android

import android.app.Application

class PaplyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        com.paply.android.dictation.DictationRuntime.recover(this)
        // Remove only obsolete Phase-0 cache recordings. Confirmed dictations now live in
        // files/dictations and are recovered above; thoughts have their own durable store.
        cacheDir.listFiles()?.filter { it.name.startsWith("dictation-") && it.extension == "wav" }
            ?.forEach { it.delete() }
    }
}
