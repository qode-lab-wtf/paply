package com.paply.android

import android.app.Application

class PaplyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // An IME dictation belongs to its input connection; process death makes it unusable.
        // Durable thought recordings live in files/thoughts and are deliberately retained.
        cacheDir.listFiles()?.filter { it.name.startsWith("dictation-") && it.extension == "wav" }
            ?.forEach { it.delete() }
    }
}
