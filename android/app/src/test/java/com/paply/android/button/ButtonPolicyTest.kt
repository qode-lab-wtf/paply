package com.paply.android.button
import org.junit.Assert.*
import org.junit.Test
import com.paply.android.button.ButtonPolicy.Phase
import com.paply.android.button.ButtonPolicy.Event

class ButtonPolicyTest {
    @Test fun visibilityRequiresAllGatesAndRejectsPasswords() {
        for (bits in 0..31) {
            val flags = (0..4).map { bits and (1 shl it) != 0 }
            assertEquals(bits == 23, ButtonPolicy.visible(flags[0],flags[1],flags[2],flags[3],flags[4]))
        }
    }
    @Test fun insertionOrderAndFailurePaths() {
        for (api in listOf(30,34,37)) {
            val calls = mutableListOf<String>()
            assertTrue(ButtonPolicy.insert(api, {true}, {calls += "commit"; true}, {calls += "paste"; true}))
            assertEquals(listOf(if (api >= 33) "commit" else "paste"), calls)
            calls.clear()
            assertFalse(ButtonPolicy.insert(api, {false}, {error("wrong field")}, {error("wrong field")}))
            assertTrue(ButtonPolicy.insert(api, {true}, {throw IllegalStateException()}, {true}))
            assertFalse(ButtonPolicy.insert(api, {true}, {false}, {false}))
        }
        var checks = 0
        assertFalse(ButtonPolicy.insert(34, { ++checks == 1 }, {false}, {error("field changed")}))
    }
    @Test fun pillStartFinishAndTerminalEvents() {
        assertEquals(Phase.STARTING, ButtonPolicy.next(Phase.IDLE, Event.START))
        assertEquals(Phase.RECORDING, ButtonPolicy.next(Phase.STARTING, Event.READY))
        for (event in listOf(Event.FINISH,Event.FIELD_CHANGE))
            assertEquals(Phase.WORKING, ButtonPolicy.next(Phase.RECORDING,event))
        for (event in listOf(Event.DISCARD,Event.SILENCE,Event.ERROR,Event.RESULT))
            for (phase in Phase.entries) assertEquals(Phase.IDLE, ButtonPolicy.next(phase,event))
        assertEquals(Phase.WORKING, ButtonPolicy.next(Phase.WORKING,Event.START))
        assertEquals(Phase.IDLE, ButtonPolicy.next(Phase.IDLE,Event.FINISH))
    }
}
