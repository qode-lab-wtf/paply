package com.paply.android

import org.junit.Assert.*
import org.junit.Test

class StartupFailureTest {
    @Test fun reportOmitsMessagesAndSuppressedDataButRetainsRetraceFrames() {
        val cause = java.security.ProviderException("secret-api-key")
        cause.stackTrace = arrayOf(StackTraceElement("a.b", "c", "SourceFile", 42))
        val error = IllegalStateException("private transcript", cause)
        error.addSuppressed(Exception("private vocabulary"))
        val report = safeStackTrace(error)
        assertTrue(report.contains("java.security.ProviderException"))
        assertTrue(report.contains("a.b.c(SourceFile:42)"))
        assertFalse(report.contains("secret-api-key"))
        assertFalse(report.contains("private"))
    }
    @Test fun cyclicCausesTerminate() {
        val first = Exception("one")
        val second = Exception("two", first)
        first.initCause(second)
        assertTrue(safeStackTrace(first).length < 24001)
    }
    @Test fun linkageErrorsRemainDiagnosable() {
        assertTrue(safeStackTrace(NoSuchMethodError("sensitive")).contains("NoSuchMethodError"))
    }
}
