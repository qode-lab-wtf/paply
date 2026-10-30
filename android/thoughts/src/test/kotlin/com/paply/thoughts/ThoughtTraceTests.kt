package com.paply.thoughts

import com.paply.thoughts.ai.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.processing.*
import com.paply.thoughts.processing.ThoughtTrace.Value.*
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.*
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class TraceRecorder {
    data class Event(val name: String, val fields: Map<String, ThoughtTrace.Value>)

    val events = CopyOnWriteArrayList<Event>()
    val trace = ThoughtTrace { n, f -> events.add(Event(n, f.toMap())) }

    fun named(n: String) = events.filter { it.name == n }.map { it.fields }

    fun assertNoContent(extra: List<String> = emptyList()) {
        val banned = listOf("tomaten", "garten", "gießen", "Tomaten gießen") + extra
        events
            .flatMap { listOf(it.name) + it.fields.values.mapNotNull { v -> (v as? S)?.value } }
            .forEach { s ->
                banned.forEach { assertFalse("Content leaked: $s", s.contains(it, true)) }
            }
    }
}

class ThoughtTraceTests {
    @Test
    fun processingLogsBeginEndAndDurationsButNeverContent() = runBlocking {
        val r = TraceRecorder()
        Harness(trace = r.trace).use { h ->
            val id = h.capture(2.0)
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            assertEquals(
                listOf(
                    "thought.transcribe.begin",
                    "thought.transcribe.end",
                    "thought.structure.begin",
                    "thought.structure.end",
                ),
                r.events.map { it.name },
            )
            val begin = r.named("thought.transcribe.begin").first()
            assertEquals(S(ThoughtTrace.short(id)), begin["id"])
            assertNotNull(begin["model"])
            assertNotNull(begin["audioS"])
            val t = r.named("thought.transcribe.end").first()
            assertEquals(S("ok"), t["result"])
            assertEquals(B(false), t["live"])
            assertEquals(
                I("ähm also die Tomaten im Garten muss ich morgen gießen".length),
                t["textLen"],
            )
            assertEquals(S("de"), t["langs"])
            assertTrue((t["ms"] as D).value >= 0)
            val start = r.named("thought.structure.begin").first()
            assertEquals(I(1), start["parts"])
            assertNotNull(start["textLen"])
            val end = r.named("thought.structure.end").first()
            assertEquals(S("ok"), end["result"])
            assertEquals(S(ThoughtStructurer.primaryModel), end["model"])
            assertEquals(B(false), end["fallback"])
            assertEquals(I(3000), end["tokens"])
            assertEquals(I(1), end["tasks"])
            assertEquals(S("new"), end["topic"])
            assertEquals(B(false), end["textIsRaw"])
            assertTrue((end["ms"] as D).value >= 0)
            r.assertNoContent()
        }
    }

    @Test
    fun waitingReasonsAreLogged() = runBlocking {
        val r = TraceRecorder()
        var flags: Flags? = null
        Harness(onSleep = { flags?.busy = false }, trace = r.trace).use { h ->
            flags = h.flags
            h.flags.online = false
            val id = h.capture()
            h.run()
            val w = r.named("thought.wait").first()
            assertEquals(S(ThoughtTrace.short(id)), w["id"])
            assertEquals(S("waitingNetwork"), w["state"])
            h.flags.online = true
            h.flags.busy = true
            h.run()
            assertEquals(ThoughtState.done, h.thought(id)?.state)
            val d = r.named("thought.wait.dictation").first()
            assertEquals(S(ThoughtTrace.short(id)), d["id"])
            assertNotNull(d["ms"])
            r.assertNoContent()
        }
    }

    @Test
    fun emptyAndUnusableAreLoggedAsCodes() = runBlocking {
        val r = TraceRecorder()
        Harness(
                MockStructurer(listOf(StructureOutcome.Unusable("invalid_output"))),
                MockTranscriber(listOf(TranscriptionResult.NoSpeech)),
                trace = r.trace,
            )
            .use { h ->
                h.capture()
                h.run()
                assertEquals(S("noSpeech"), r.named("thought.transcribe.end").first()["result"])
                assertEquals(1, r.named("thought.empty").size)
                h.capture()
                h.run()
                val end = r.named("thought.structure.end").last()
                assertEquals(S("raw"), end["result"])
                assertEquals(S("invalid_output"), end["code"])
                r.assertNoContent()
            }
    }

    @Test
    fun structurerLogsEveryCallWithStatusTokensAndNextStep() = runBlocking {
        val r = TraceRecorder()
        MockWebServer().use { s ->
            s.enqueue(mockError(429, "rate_limit_exceeded", "600"))
            s.enqueue(AIFixture.reply(AIFixture.answer(), total = 3412))
            val o =
                withContext(ThoughtTrace.ThoughtID("s_abcdef12")) {
                    ThoughtStructurer(baseURL = s.url("/"), trace = r.trace)
                        .structure(AIFixture.input(), "test-placeholder")
                }
            assertTrue(o is StructureOutcome.Success)
            val c = r.named("thought.groq")
            assertEquals(2, c.size)
            assertEquals(S(ThoughtStructurer.primaryModel), c[0]["model"])
            assertEquals(S("http-429"), c[0]["status"])
            assertEquals(S("rate_limit_exceeded"), c[0]["groqCode"])
            assertEquals(D(600.0), c[0]["retryAfterS"])
            assertEquals(S("fallback"), c[0]["next"])
            assertEquals(S(ThoughtStructurer.fallbackModel), c[1]["model"])
            assertEquals(S("ok"), c[1]["status"])
            assertEquals(I(3412), c[1]["tokens"])
            assertEquals(B(true), c[1]["valid"])
            assertEquals(S("done"), c[1]["next"])
            assertEquals(S("stop"), c[1]["finish"])
            assertEquals(S("low"), c[1]["effort"])
            assertTrue(c.all { it["id"] == S("s_abcdef12") && it["ms"] != null })
            r.assertNoContent(listOf("Oranienstraße", "Wohnung", "Makler", "Unterlagen", "Schufa"))
        }
    }

    @Test
    fun invalidOutputRetriesWithMediumAndLogsBothCalls() = runBlocking {
        val r = TraceRecorder()
        MockWebServer().use { s ->
            s.enqueue(mockError(400, "json_validate_failed"))
            s.enqueue(AIFixture.reply(AIFixture.answer()))
            ThoughtStructurer(baseURL = s.url("/"), trace = r.trace)
                .structure(AIFixture.input(), "test-placeholder")
            val c = r.named("thought.groq")
            assertEquals(listOf(S("http-400"), S("ok")), c.map { it["status"] })
            assertEquals(listOf(S("medium"), S("done")), c.map { it["next"] })
            assertEquals(listOf(S("low"), S("medium")), c.map { it["effort"] })
        }
    }

    @Test
    fun ledgerRefusalIsAWaitingReason() = runBlocking {
        val r = TraceRecorder()
        MockWebServer().use { s ->
            val l = tempLedger(TokenLedger.Limits(dailyTokens = 100))
            assertEquals(
                StructureOutcome.Unusable("budget_small"),
                ThoughtStructurer(l, baseURL = s.url("/"), trace = r.trace)
                    .structure(AIFixture.input(), "test-placeholder"),
            )
            assertEquals(S("tooSmall"), r.named("thought.groq.ledger").first()["reason"])
            assertTrue(r.named("thought.groq").isEmpty())
            assertEquals(0, s.requestCount)
        }
    }
}
