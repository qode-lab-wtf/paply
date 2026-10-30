package com.paply.thoughts

import com.paply.thoughts.model.*
import org.junit.Assert.*
import org.junit.Test

class BetaFeaturesTests {
    @Test
    fun defaultsToOn() {
        assertEquals("paply.beta.thoughts", BetaFeatures.thoughtsKey)
        assertTrue(BetaFeatures.thoughtsEnabled(null))
        val d = mutableMapOf<String, Any?>()
        assertTrue(BetaFeatures.thoughtsEnabled(d))
        d[BetaFeatures.thoughtsKey] = false
        assertFalse(BetaFeatures.thoughtsEnabled(d))
        d[BetaFeatures.thoughtsKey] = true
        assertTrue(BetaFeatures.thoughtsEnabled(d))
        d[BetaFeatures.thoughtsKey] = "aus"
        assertTrue(BetaFeatures.thoughtsEnabled(d))
    }

    @Test
    fun launchArgumentShowsOffWithoutSaving() {
        val d = mutableMapOf<String, Any?>()
        assertTrue(BetaFeatures.thoughtsAtLaunch(d, listOf("Paply")))
        assertFalse(
            BetaFeatures.thoughtsAtLaunch(d, listOf("Paply", "-PaplyBetaOff"), debug = true),
        )
        assertTrue(
            BetaFeatures.thoughtsAtLaunch(d, listOf("Paply", "-PaplyBetaOff"), debug = false),
        )
        assertTrue(d.isEmpty())
        d[BetaFeatures.thoughtsKey] = false
        assertFalse(BetaFeatures.thoughtsAtLaunch(d, listOf("Paply")))
    }

    /** TaskReminderPlan integration belongs to Part B; retain the shared wire-format cases here. */
    @Test
    fun widgetUsesTheSameReminderIdentifierAsTheApp() {
        listOf("s_1" to "k_1", "s_8F2A" to "k_x-y", "s_a b" to "k_ü").forEach { (s, k) ->
            val id = TaskReminderID.identifier(s, k)
            assertEquals("task/$s/$k", id)
            val parts = id.split('/')
            assertEquals(s, parts[1])
            assertEquals(k, parts[2])
        }
    }

    @Test
    fun startCheckAfterEveryAwait() {
        val g = ThoughtStartGate()
        g.begin()
        repeat(3) { assertTrue(g.allows(true)) }
        g.begin()
        assertFalse(g.allows(false))
        g.begin()
        assertTrue(g.allows(true))
        g.abort()
        assertFalse(g.allows(false))
        assertFalse(g.allows(true))
        assertTrue(g.aborted)
        g.begin()
        assertFalse(g.allows(false))
        g.begin()
        assertFalse(g.aborted)
        assertTrue(g.allows(true))
    }
}
