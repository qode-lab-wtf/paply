package com.paply.android.thoughts

import com.paply.android.safeError
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Test

class CaptureErrorTest {
    @Test fun startFailureDoesNotAskForAKeyBecauseCaptureWorksWithoutOne() {
        assertEquals("Aufnahme nicht möglich. Prüfe Mikrofon-Erlaubnis und freien Speicher.", safeError(IllegalStateException()))
    }
    @Test fun storageFailureAlsoRecognizesWrappedIoErrors() {
        assertEquals("Speicher voll – schaffe Platz.", safeError(IOException()))
        assertEquals("Speicher voll – schaffe Platz.", safeError(IllegalStateException(IOException("ENOSPC"))))
    }
}
