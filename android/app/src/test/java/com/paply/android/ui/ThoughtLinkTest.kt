package com.paply.android.ui

import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ThoughtLinkTest {
    @Test fun consumedLinkIsAbsentFromRecreatedActivityIntent() {
        val intent = Intent().putExtra("thoughtId", "first").putExtra("unrelated", "keep")
        consumeThoughtLink(intent, "first")
        val recreatedIntent = Intent(intent)
        assertNull(recreatedIntent.getStringExtra("thoughtId"))
        assertEquals("keep", recreatedIntent.getStringExtra("unrelated"))
        consumeThoughtLink(intent, "first")
        assertFalse(intent.hasExtra("thoughtId"))
    }
    @Test fun consumptionCannotDiscardANewerNotification() {
        val intent = Intent().putExtra("thoughtId", "new")
        consumeThoughtLink(intent, "old")
        assertEquals("new", intent.getStringExtra("thoughtId"))
        consumeThoughtLink(intent, "new")
        assertFalse(intent.hasExtra("thoughtId"))
    }
}
