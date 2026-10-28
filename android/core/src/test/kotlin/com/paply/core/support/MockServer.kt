package com.paply.core

import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*

internal class MockServer(private val handler: (RecordedRequest, Int) -> MockResponse) :
    AutoCloseable {
    val server = MockWebServer()
    val requests = CopyOnWriteArrayList<RecordedRequest>()
    val stoppedCount = AtomicInteger()
    val attempts = CopyOnWriteArrayList<String>()
    val networkFailures = CopyOnWriteArrayList<String>()
    val timeouts = CopyOnWriteArrayList<Pair<String, Int>>()
    private val resources = CopyOnWriteArrayList<AutoCloseable>()
    val transport = GroqTransport {
        GroqTransport.defaultHttp()
            .newBuilder()
            .eventListener(
                object : EventListener() {
                    override fun callStart(call: Call) {
                        attempts += call.request().url.encodedPath
                    }

                    override fun callFailed(call: Call, ioe: java.io.IOException) {
                        networkFailures +=
                            "${call.request().url.encodedPath}: ${ioe.javaClass.simpleName}: ${ioe.message}"
                    }

                    override fun canceled(call: Call) {
                        stoppedCount.incrementAndGet()
                    }
                },
            )
            .addInterceptor { chain ->
                timeouts += chain.request().url.encodedPath to chain.readTimeoutMillis()
                chain.proceed(chain.request())
            }
            .build()
    }
    private val key = "offline-test-${UUID.randomUUID()}"

    init {
        server.dispatcher =
            object : okhttp3.mockwebserver.Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val index: Int
                    synchronized(requests) {
                        index = requests.count { it.path == request.path }
                        requests += request
                    }
                    return handler(request, index)
                }
            }
        server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
    }

    // Pin the loopback address: localhost also resolves to ::1 on macOS, while this server
    // listens on IPv4. A broken connection must exercise retry, not an unrelated DNS route.
    fun client(retryDelay: Double = 0.01, clock: PaplyClock = SystemPaplyClock) =
        GroqClient(
                key,
                server.url("/openai/v1/").newBuilder().host("127.0.0.1").build(),
                transport = transport,
                clock = clock,
            )
            .also { it.retryDelaySeconds = retryDelay }

    fun requests(suffix: String) = requests.filter { it.path?.endsWith(suffix) == true }

    fun catalog(clock: PaplyClock = SystemPaplyClock) = ModelCatalog(clock).also { resources += it }

    fun pipeline(
        settings: PaplySettings =
            PaplySettings(spokenLanguages = listOf("de", "en"), primaryLanguage = "de"),
        options: PipelineOptions = PipelineOptions(),
        history: List<String> = emptyList(),
        onState: (DictationStatus) -> Unit = {},
    ) =
        DictationPipeline(
                settings,
                client(),
                catalog(),
                options,
                history,
                listOf("de-DE"),
                onState = onState,
            )
            .also { resources += it }

    override fun close() {
        resources.asReversed().forEach { it.close() }
        server.close()
    }
}

internal val RecordedRequest.bodyText: String
    get() = body.clone().readUtf8()
internal val RecordedRequest.json: JsonObject
    get() = Json.parseToJsonElement(bodyText).jsonObject

internal fun RecordedRequest.field(name: String): String? {
    val marker = "name=\"$name\"\r\n"
    val text = bodyText
    val index = text.indexOf(marker)
    if (index < 0) return null
    val rest = text.substring(index + marker.length)
    val end = rest.indexOf("\r\n\r\n")
    val value =
        if (rest.startsWith("\r\n")) rest.substring(2)
        else if (end >= 0) rest.substring(end + 4) else return null
    return value.substringBefore("\r\n--")
}

internal object Groq {
    fun raw(body: String, status: Int = 200) = MockResponse().setResponseCode(status).setBody(body)

    fun models(vararg ids: String) =
        raw(
            buildJsonObject {
                put(
                    "data",
                    buildJsonArray { ids.forEach { add(buildJsonObject { put("id", it) }) } },
                )
            }
                .toString(),
        )

    fun transcription(text: String, language: String = "German", logprob: Double = -0.2) =
        raw(
            buildJsonObject {
                put("text", " $text")
                put("language", language)
                put("duration", 3.0)
                put(
                    "segments",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("text", " $text")
                                put("start", 0.0)
                                put("end", 3.0)
                                put("avg_logprob", logprob)
                                put("no_speech_prob", 0.0)
                                put("compression_ratio", 1.1)
                            },
                        )
                    },
                )
            }
                .toString(),
        )

    fun chat(content: String, finish: String = "stop"): MockResponse {
        val lines = mutableListOf<String>()
        fun event(o: JsonObject) {
            lines += "data: $o\n\n"
        }
        event(
            buildJsonObject {
                put(
                    "choices",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put(
                                    "delta",
                                    buildJsonObject {
                                        put("role", "assistant")
                                        put("content", "")
                                    },
                                )
                                put("finish_reason", JsonNull)
                            },
                        )
                    },
                )
            },
        )
        for (chunk in content.scalars().toList().chunked(7)) event(
            buildJsonObject {
                put(
                    "choices",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put(
                                    "delta",
                                    buildJsonObject {
                                        put("content", chunk.joinToString("") { it.scalarString() })
                                    },
                                )
                                put("finish_reason", JsonNull)
                            },
                        )
                    },
                )
            },
        )
        event(
            buildJsonObject {
                put(
                    "choices",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("delta", JsonObject(emptyMap()))
                                put("finish_reason", finish)
                            },
                        )
                    },
                )
            },
        )
        lines += "data: [DONE]\n\n"
        return raw(lines.joinToString("")).setHeader("Content-Type", "text/event-stream")
    }

    fun chatJSON(content: String, finish: String = "stop") =
        raw(
            buildJsonObject {
                put(
                    "choices",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("finish_reason", finish)
                                put(
                                    "message",
                                    buildJsonObject {
                                        put("content", content)
                                        put("reasoning", "Niemals ausgeben")
                                    },
                                )
                            },
                        )
                    },
                )
            }
                .toString(),
        )

    fun error(
        status: Int,
        code: String? = null,
        retryAfter: String? = null,
        message: String = "Fehler",
    ): MockResponse =
        raw(
                buildJsonObject {
                    put(
                        "error",
                        buildJsonObject {
                            put("message", message)
                            code?.let { put("code", it) }
                        },
                    )
                }
                    .toString(),
                status,
            )
            .apply { retryAfter?.let { setHeader("Retry-After", it) } }
}

internal fun MockResponse.delayed(seconds: Double): MockResponse =
    if (seconds >= 5)
        setSocketPolicy(
            SocketPolicy.NO_RESPONSE,
        ) // Waits for cancellation without sleeping a MockWebServer worker.
    else setBodyDelay((seconds * 1000).toLong(), TimeUnit.MILLISECONDS)

internal suspend fun eventually(timeoutMillis: Long = 3000, condition: () -> Boolean) {
    withTimeout(timeoutMillis) { while (!condition()) delay(5) }
}

internal suspend fun failure(block: suspend () -> Any?): GroqFailure {
    try {
        block()
        fail("Expected GroqFailure")
    } catch (f: GroqFailure) {
        return f
    }
    error("unreachable")
}

internal class FakeClock(var millis: Long = 0) : PaplyClock {
    val sleeps = mutableListOf<Double>()

    override fun nowMillis() = millis

    override fun monotonicNanos() = millis * 1_000_000

    override suspend fun sleep(seconds: Double) {
        sleeps += seconds
        millis += (seconds * 1000).toLong()
        yield()
    }
}

internal fun eq(a: Any?, b: Any?): Boolean =
    if (a is Number && b is Number) a.toDouble() == b.toDouble() else a == b

internal fun expect(value: Boolean) = assertTrue(value)

internal fun echoPolish(request: RecordedRequest): MockResponse {
    val messages = request.json["messages"]!!.jsonArray
    val payload = Json.parseToJsonElement(messages.last().jsonObject.string("content")!!).jsonObject
    return Groq.chat(payload.string("current_dictation")!!)
}

internal fun standardServer(
    text: String = "Hallo zusammen.",
    transcriptionDelay: Double = 0.0,
    chatDelay: Double = 0.0,
    modelsDelay: Double = 0.0,
) = MockServer { request, _ ->
    when {
        request.path!!.endsWith("/models") -> Groq.models(GroqModels.polish).delayed(modelsDelay)
        request.path!!.endsWith("/chat/completions") -> echoPolish(request).delayed(chatDelay)
        else -> Groq.transcription(text).delayed(transcriptionDelay)
    }
}
