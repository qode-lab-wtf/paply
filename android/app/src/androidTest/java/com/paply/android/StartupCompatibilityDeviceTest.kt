package com.paply.android

import androidx.test.platform.app.InstrumentationRegistry
import com.paply.thoughts.model.Parallel
import com.paply.thoughts.store.ThoughtStore
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class StartupCompatibilityDeviceTest {
    @Test fun jvmModuleStreamCallsWorkOnTheDeviceApi() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "startup-compatibility-${System.nanoTime()}")
        try {
            val store = ThoughtStore(root.toPath())
            assertTrue(store.recover().isEmpty())
            assertEquals(listOf(0, 2, 4), Parallel.map(3) { it * 2 })
        } finally { root.deleteRecursively() }
    }
}
