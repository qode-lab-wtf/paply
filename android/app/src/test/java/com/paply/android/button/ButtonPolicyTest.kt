package com.paply.android.button
import org.junit.Assert.*
import org.junit.Test
import com.paply.android.button.ButtonTextInsertion.Result.*
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
        for (api in listOf(29,30,31,32,33,34,37)) {
            for (primarySuccess in listOf(false, true)) {
                val calls = mutableListOf<String>()
                assertEquals(VERIFIED, ButtonPolicy.insert(api, {true},
                    { calls += "commit"; primarySuccess },
                    { calls += "set"; if (primarySuccess) VERIFIED else UNAVAILABLE },
                    { calls += "paste"; true }))
                assertEquals(listOf(if (api >= 33) "commit" else "set") +
                    if (primarySuccess) emptyList() else listOf("paste"), calls)
            }
            assertEquals(UNAVAILABLE, ButtonPolicy.insert(api, {false}, {error("wrong field")},
                {error("wrong field")}, {error("wrong field")}))
            assertEquals(VERIFIED, ButtonPolicy.insert(api, {true}, {error("unsupported")}, {error("unsupported")}, {true}))
            assertEquals(UNAVAILABLE, ButtonPolicy.insert(api, {true}, {false}, {UNAVAILABLE}, {false}))
            var checks = 0
            assertEquals(UNAVAILABLE, ButtonPolicy.insert(api, { ++checks == 1 }, {false}, {UNAVAILABLE}, {error("field changed")}))
        }
    }
    @Test fun repeatedFinishDiscardFinishReturnsToFreshRecording() {
        var phase = Phase.IDLE
        fun step(event: Event, expected: Phase) {
            phase = ButtonPolicy.next(phase, event)
            assertEquals(expected, phase)
        }
        repeat(3) { round ->
            step(Event.START, Phase.STARTING)
            step(Event.READY, Phase.RECORDING)
            if (round == 1) step(Event.DISCARD, Phase.IDLE)
            else {
                step(Event.FINISH, Phase.WORKING)
                step(Event.START, Phase.WORKING)
                step(Event.SUCCESS, Phase.SUCCESS)
                step(Event.RESULT, Phase.IDLE)
            }
        }
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
