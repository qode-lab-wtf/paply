package com.paply.thoughts

import com.paply.core.*
import com.paply.thoughts.ai.*
import com.paply.thoughts.budget.TokenLedger
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

fun mockError(status: Int, code: String = "http", retry: String? = null) =
    MockResponse().setResponseCode(status).setBody("""{"error":{"code":"$code"}}""").apply {
        if (retry != null) setHeader("Retry-After", retry)
    }

fun tempLedger(
    limits: TokenLedger.Limits = TokenLedger.Limits(),
    now: () -> Instant = Instant::now,
) = TokenLedger(StoreSupport.temporaryRoot().resolve("ledger.json"), { limits }, now)

fun MockWebServer.structurer(ledger: TokenLedger? = null, now: () -> Instant = Instant::now) =
    ThoughtStructurer(ledger = ledger, baseURL = url("/"), now = now, sleep = {})

fun MockWebServer.body() = Json.parseToJsonElement(takeRequest().body.readUtf8()).jsonObject

fun structuredRequest(): StructuredChatRequest {
    val b = ThoughtPrompt.build(AIFixture.input())
    return StructuredChatRequest(
        ThoughtStructurer.primaryModel,
        b.system,
        b.user,
        ThoughtSchema.name,
        ThoughtSchema.data(ThoughtSchema.full),
        b.maxCompletionTokens,
    )
}

class AIChatStructuredTests {
    @Test
    fun requestBodyUsesStrictSchemaWithoutStream() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(AIFixture.reply(AIFixture.answer()))
            GroqClient("test-placeholder", s.url("/")).chatStructured(structuredRequest())
            val j = s.body()
            assertEquals("openai/gpt-oss-120b", j["model"]!!.jsonPrimitive.content)
            assertEquals(0.1, j["temperature"]!!.jsonPrimitive.double, 0.0)
            assertEquals("low", j["reasoning_effort"]!!.jsonPrimitive.content)
            assertEquals(
                ThoughtPrompt.maxCompletionTokens(AIFixture.transcript),
                j["max_completion_tokens"]!!.jsonPrimitive.int,
            )
            assertNull(j["stream"])
            val f = j["response_format"]!!.jsonObject
            assertEquals("json_schema", f["type"]!!.jsonPrimitive.content)
            val schema = f["json_schema"]!!.jsonObject
            assertEquals("paply_thought", schema["name"]!!.jsonPrimitive.content)
            assertEquals(JsonPrimitive(true), schema["strict"])
            assertEquals(ThoughtSchema.full, schema["schema"])
            assertEquals(
                listOf("system", "user"),
                j["messages"]!!.jsonArray.map { it.jsonObject["role"]!!.jsonPrimitive.content },
            )
            assertEquals(
                ThoughtPrompt.system,
                j["messages"]!!.jsonArray[0].jsonObject["content"]!!.jsonPrimitive.content,
            )
            assertEquals(120.0, structuredIdleTimeout, 0.0)
        }
    }

    @Test
    fun successCarriesContentFinishAndUsage() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(AIFixture.reply("{}", total = 3412))
            assertEquals(
                StructuredChatResponse("{}", "stop", TokenUsage(2512, 900, 3412)),
                GroqClient("test-placeholder", s.url("/")).chatStructured(structuredRequest()),
            )
        }
    }

    @Test
    fun truncatedAnswerIsReportedNotHidden() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(AIFixture.reply("{\"title\":", finish = "length"))
            assertEquals(
                "length",
                GroqClient("test-placeholder", s.url("/"))
                    .chatStructured(structuredRequest())
                    .finishReason,
            )
        }
    }

    @Test
    fun rateLimitKeepsRetryAfter() = runBlocking {
        listOf("0.5" to 0.5, "432" to 432.0).forEach { (h, n) ->
            MockWebServer().use { s ->
                s.enqueue(mockError(429, "rate_limit_exceeded", h))
                val e =
                    runCatching {
                        GroqClient("test-placeholder", s.url("/"))
                            .chatStructured(structuredRequest())
                    }
                        .exceptionOrNull() as GroqFailure
                assertEquals(429, e.status)
                assertEquals(n, e.retryAfter!!, 0.0)
                assertEquals(1, s.requestCount)
            }
        }
    }

    @Test
    fun schemaViolationKeepsGroqCode() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(400, "json_validate_failed"))
            val e =
                runCatching {
                    GroqClient("test-placeholder", s.url("/")).chatStructured(structuredRequest())
                }
                    .exceptionOrNull() as GroqFailure
            assertEquals(400, e.status)
            assertEquals("json_validate_failed", e.code)
        }
    }

    /**
     * iOS's eval-only diagnosed API is not shipped in Android V1; production must discard
     * failed_generation.
     */
    @Test
    fun productionCallDiscardsFailedGeneration() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(
                MockResponse()
                    .setResponseCode(400)
                    .setBody(
                        """{"error":{"code":"json_validate_failed","failed_generation":"PRIVATE-THOUGHT"}}""",
                    ),
            )
            val e =
                runCatching {
                    GroqClient("test-placeholder", s.url("/")).chatStructured(structuredRequest())
                }
                    .exceptionOrNull() as GroqFailure
            assertEquals("json_validate_failed", e.code)
            assertFalse(e.toString().contains("PRIVATE-THOUGHT"))
            assertNull(e.cause)
        }
    }

    @Test
    fun unauthorizedAndNetwork() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(401, "invalid_api_key"))
            assertEquals(
                401,
                (runCatching {
                        GroqClient("test-placeholder", s.url("/"))
                            .chatStructured(structuredRequest())
                    }
                        .exceptionOrNull() as GroqFailure)
                    .status,
            )
            s.enqueue(
                MockResponse()
                    .setBody("x".repeat(1024))
                    .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY),
            )
            assertEquals(
                "network",
                (runCatching {
                        GroqClient("test-placeholder", s.url("/"))
                            .chatStructured(structuredRequest())
                    }
                        .exceptionOrNull() as GroqFailure)
                    .code,
            )
        }
    }
}

class AIStructurerTests {
    private val f = AIFixture

    private suspend fun run(
        s: MockWebServer,
        l: TokenLedger? = null,
        input: StructureInput = f.input(),
    ) = s.structurer(l).structure(input, "test-placeholder")

    @Test
    fun successValidatesAndSettlesTheLedger() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(f.reply(f.answer(), total = 3412))
            val l = tempLedger()
            val o = run(s, l) as StructureOutcome.Success
            assertEquals(ThoughtStructurer.primaryModel, o.model)
            assertEquals(3412, o.usage.total)
            assertEquals(TopicDecision.Existing("t_umzug"), o.result.topic)
            assertEquals(f.goodClean, o.result.cleanText)
            assertEquals(3412, l.summary().tokens)
        }
    }

    @Test
    fun shortRateLimitWaitsOnceOnTheSameModel() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(429, retry = "0.1"))
            s.enqueue(f.reply(f.answer()))
            assertEquals(ThoughtStructurer.primaryModel, (run(s) as StructureOutcome.Success).model)
            assertEquals(s.body()["model"], s.body()["model"])
        }
    }

    @Test
    fun longRateLimitSwitchesTo20bOnce() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(429, retry = "600"))
            s.enqueue(f.reply(f.answer()))
            assertEquals(
                ThoughtStructurer.fallbackModel,
                (run(s) as StructureOutcome.Success).model,
            )
            assertEquals(2, s.requestCount)
        }
    }

    @Test
    fun bothModelsLimitedMeansWaitingLimitForAtLeast15Minutes() = runBlocking {
        val now = Instant.ofEpochSecond(1800000000)
        MockWebServer().use { s ->
            repeat(2) { s.enqueue(mockError(429, retry = "120")) }
            val l = tempLedger(now = { now })
            val o = s.structurer(l, { now }).structure(f.input(), "test-placeholder")
            assertEquals(
                StructureOutcome.Wait(
                    ThoughtState.waitingLimit,
                    now.plusSeconds(900),
                    "Groq-Limit · später erneut",
                ),
                o,
            )
            assertEquals(2, s.requestCount)
            assertEquals(0, l.summary().tokens)
        }
    }

    @Test
    fun missingModelFallsBackThenGivesUp() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(404, "model_not_found"))
            s.enqueue(f.reply(f.answer()))
            assertEquals(
                ThoughtStructurer.fallbackModel,
                (run(s) as StructureOutcome.Success).model,
            )
            repeat(2) { s.enqueue(mockError(404, "model_not_found")) }
            assertEquals(StructureOutcome.Unusable("model_missing"), run(s))
        }
    }

    @Test
    fun schemaFailureRetriesOnceWithMediumEffort() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(400, "json_validate_failed"))
            s.enqueue(f.reply(f.answer()))
            assertTrue(run(s) is StructureOutcome.Success)
            assertEquals(
                listOf("low", "medium"),
                List(2) { s.body()["reasoning_effort"]!!.jsonPrimitive.content },
            )
        }
    }

    @Test
    fun truncatedOrUnreadableTwiceIsUnusable() = runBlocking {
        listOf(
                "{\"title\":" to "length",
                "kein json" to "stop",
                f.answer(title = "", clean = "") to "stop",
            )
            .forEach { (text, finish) ->
                MockWebServer().use { s ->
                    repeat(2) { s.enqueue(f.reply(text, finish)) }
                    assertEquals(StructureOutcome.Unusable("invalid_output"), run(s))
                    assertEquals(
                        listOf("low", "medium"),
                        List(2) { s.body()["reasoning_effort"]!!.jsonPrimitive.content },
                    )
                }
            }
    }

    @Test
    fun unauthorizedMeansWaitingKeyAndSettlesWithZero() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(401, "invalid_api_key"))
            val l = tempLedger()
            assertEquals(
                StructureOutcome.Wait(ThoughtState.waitingKey, null, "Groq-Schlüssel prüfen"),
                run(s, l),
            )
            assertEquals(0, l.summary().tokens)
            assertEquals(
                StructureOutcome.Wait(ThoughtState.waitingKey, null, "Groq-Schlüssel fehlt"),
                s.structurer().structure(f.input(), "  "),
            )
            assertEquals(1, s.requestCount)
        }
    }

    @Test
    fun networkLossMeansWaitingNetworkAndKeepsTheEstimate() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(
                MockResponse()
                    .setBody("x".repeat(1024))
                    .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY),
            )
            val l = tempLedger()
            assertEquals(
                StructureOutcome.Wait(ThoughtState.waitingNetwork, null, "Wartet auf Netz"),
                run(s, l),
            )
            assertEquals(ThoughtPrompt.build(f.input()).estimate, l.summary().tokens)
            MockWebServer().use { broken ->
                broken.enqueue(mockError(503))
                assertEquals(
                    StructureOutcome.Wait(
                        ThoughtState.waitingNetwork,
                        null,
                        "Groq ist gerade gestört",
                    ),
                    run(broken),
                )
            }
        }
    }

    @Test
    fun fullLedgerWaitsWithoutRequest() = runBlocking {
        val now = Instant.ofEpochSecond(1800000000)
        val l = tempLedger(TokenLedger.Limits(dailyTokens = 9000), { now })
        l.reserve("x", 7000, TokenLedger.Unit.tokens)
        MockWebServer().use { s ->
            assertEquals(
                StructureOutcome.Wait(
                    ThoughtState.waitingBudget,
                    now.plusSeconds(86400),
                    "Gedanken-Budget für heute erreicht",
                ),
                run(s, l),
            )
            assertEquals(0, s.requestCount)
            assertEquals(
                StructureOutcome.Unusable("budget_small"),
                run(s, tempLedger(TokenLedger.Limits(dailyTokens = 1000))),
            )
        }
    }

    @Test
    fun hugeTranscriptIsTooLarge() = runBlocking {
        MockWebServer().use { s ->
            assertEquals(
                StructureOutcome.Unusable("too_large"),
                run(
                    s,
                    input =
                        f.input(
                            transcript =
                                "Das ist ein sehr langer Gedanke über die Wohnung. ".repeat(500),
                        ),
                ),
            )
            assertEquals(0, s.requestCount)
        }
    }

    @Test
    fun partModeUsesThePartPromptAndSchema() = runBlocking {
        MockWebServer().use { s ->
            val json = buildJsonObject {
                put("clean_text", f.goodClean)
                put(
                    "tasks",
                    JsonArray(
                        listOf(
                            f.task(
                                "Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                            ),
                        ),
                    ),
                )
            }
            s.enqueue(f.reply(json.toString()))
            val r =
                (run(s, input = f.input(part = StructureInput.Part(2, 3)))
                        as StructureOutcome.Success)
                    .result
            assertEquals(f.goodClean, r.cleanText)
            assertEquals(1, r.tasks.size)
            assertTrue(r.title.isEmpty())
            val j = s.body()
            assertEquals(
                "paply_thought_part",
                j["response_format"]!!
                    .jsonObject["json_schema"]!!
                    .jsonObject["name"]!!
                    .jsonPrimitive
                    .content,
            )
            val system = j["messages"]!!.jsonArray[0].jsonObject["content"]!!.jsonPrimitive.content
            assertTrue(system.startsWith("This is part 2 of 3 of one long spoken thought."))
            assertFalse(system.contains("RELATED"))
        }
    }

    @Test
    fun neverUsesQwen() = runBlocking {
        MockWebServer().use { s ->
            repeat(2) { s.enqueue(mockError(429, retry = "900")) }
            run(s)
            repeat(s.requestCount) {
                assertTrue(s.body()["model"]!!.jsonPrimitive.content.startsWith("openai/gpt-oss"))
            }
        }
    }

    @Test
    fun modelsComeFromTheClosure() = runBlocking {
        MockWebServer().use { s ->
            var chosen = ThoughtStructurer.Models(ThoughtStructurer.fallbackModel, null)
            val c = ThoughtStructurer(baseURL = s.url("/"), models = { chosen })
            s.enqueue(f.reply(f.answer()))
            assertEquals(
                ThoughtStructurer.fallbackModel,
                (c.structure(f.input(), "test-placeholder") as StructureOutcome.Success).model,
            )
            chosen = ThoughtStructurer.Models.standard
            s.enqueue(f.reply(f.answer()))
            assertEquals(
                ThoughtStructurer.primaryModel,
                (c.structure(f.input(), "test-placeholder") as StructureOutcome.Success).model,
            )
        }
    }

    @Test
    fun withoutFallbackA404GivesUpAtOnce() = runBlocking {
        MockWebServer().use { s ->
            s.enqueue(mockError(404, "model_not_found"))
            assertEquals(
                StructureOutcome.Unusable("model_missing"),
                ThoughtStructurer(
                        baseURL = s.url("/"),
                        models = {
                            ThoughtStructurer.Models(
                                ThoughtStructurer.fallbackModel,
                                ThoughtStructurer.fallbackModel,
                            )
                        },
                    )
                    .structure(f.input(), "test-placeholder"),
            )
            assertEquals(1, s.requestCount)
        }
    }

    @Test
    fun nowIsTheRecordingTimeWhenKnown() = runBlocking {
        MockWebServer().use { s ->
            val d = Instant.ofEpochSecond(1793095200)
            s.enqueue(f.reply(f.answer()))
            s.structurer(now = { d.plusSeconds(2 * 86400) })
                .structure(f.input().copy(recordedAt = d), "test-placeholder")
            assertEquals(
                ThoughtPrompt.nowLabel(d, "de"),
                Json.parseToJsonElement(
                        s.body()["messages"]!!
                            .jsonArray
                            .last()
                            .jsonObject["content"]!!
                            .jsonPrimitive
                            .content,
                    )
                    .jsonObject["now"]!!
                    .jsonPrimitive
                    .content,
            )
        }
    }

    @Test
    fun requestCarriesNowFromTheClock() = runBlocking {
        MockWebServer().use { s ->
            val d = Instant.ofEpochSecond(1793095200)
            s.enqueue(f.reply(f.answer()))
            s.structurer(now = { d }).structure(f.input(), "test-placeholder")
            assertEquals(
                ThoughtPrompt.nowLabel(d, "de"),
                Json.parseToJsonElement(
                        s.body()["messages"]!!
                            .jsonArray
                            .last()
                            .jsonObject["content"]!!
                            .jsonPrimitive
                            .content,
                    )
                    .jsonObject["now"]!!
                    .jsonPrimitive
                    .content,
            )
        }
    }
}
