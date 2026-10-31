package com.paply.core

import java.io.File
import java.io.IOException
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Safe classification only. Server messages, credentials and dictation content are never retained.
 */
class GroqFailure(
    val status: Int = 0,
    val code: String = "network",
    val retryAfter: Double? = null,
) : IOException(if (status == 0) code else "http-$status") {
    val modelMissing
        get() =
            status == 404 ||
                (status == 400 && code in listOf("model_decommissioned", "model_not_found"))

    val retryable
        get() =
            if (status != 0) status in listOf(408, 409, 429) || status >= 500
            else code != "cancelled"

    val polishCode
        get() =
            when {
                status == 429 -> PolishFailureCode.rateLimited
                status == 401 || status == 403 -> PolishFailureCode.unauthorized
                status >= 500 -> PolishFailureCode.serverError
                status > 0 -> PolishFailureCode.requestRejected
                code == "invalid-response" -> PolishFailureCode.invalidResponse
                code == "cancelled" -> PolishFailureCode.cancelled
                else -> PolishFailureCode.network
            }

    val germanMessage
        get() =
            when {
                status == 401 || status == 403 ->
                    "Ungültiger Groq-Schlüssel – bitte in den Einstellungen prüfen."
                status == 429 -> "Groq-Limit erreicht – bitte später erneut versuchen."
                status == 413 -> "Die Aufnahme ist zu lang für eine Übertragung."
                status >= 500 ->
                    "Groq ist gerade gestört (Fehler $status) – bitte erneut versuchen."
                status > 0 -> "Transkription fehlgeschlagen (Fehler $status)."
                code == "invalid-response" ->
                    "Groq hat eine unlesbare Antwort geschickt – bitte erneut versuchen."
                code == "cancelled" -> "Abgebrochen."
                else -> "Keine Verbindung – Netzwerk prüfen und erneut versuchen."
            }

    val dictationError
        get() =
            when (polishCode) {
                PolishFailureCode.rateLimited -> DictationError.rateLimited
                PolishFailureCode.unauthorized -> DictationError.unauthorized
                PolishFailureCode.serverError -> DictationError.serverError
                PolishFailureCode.requestRejected -> DictationError.requestRejected
                PolishFailureCode.invalidResponse -> DictationError.invalidResponse
                PolishFailureCode.cancelled -> DictationError.cancelled
                else -> DictationError.network
            }
}

/**
 * Each request reads the current transport. Reset retires connections without cancelling in-flight
 * calls.
 */
class GroqTransport(private val factory: () -> OkHttpClient = { defaultHttp() }) {
    @Volatile private var current = factory()

    fun client(): OkHttpClient = current

    @Synchronized
    fun reset() {
        val old = current
        current = factory()
        old.connectionPool.evictAll()
    }

    companion object {
        val shared = GroqTransport()

        fun defaultHttp() =
            OkHttpClient.Builder()
                .callTimeout(0, TimeUnit.MILLISECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .connectTimeout(20, TimeUnit.SECONDS)
                .retryOnConnectionFailure(false)
                .followRedirects(false)
                .followSslRedirects(false)
                .cookieJar(CookieJar.NO_COOKIES)
                .cache(null)
                .build()
    }
}

class GroqClient(
    internal val apiKey: String,
    internal val baseUrl: HttpUrl = defaultBaseURL,
    private val http: OkHttpClient? = null,
    private val diagnostic: (String) -> Unit = {},
    internal val transport: GroqTransport = GroqTransport.shared,
    internal val clock: PaplyClock = SystemPaplyClock,
    private val reachability: NetworkReachability = AssumeReachable,
) {
    var maxRetryAfterSeconds = 20.0
    var retryDelaySeconds = 0.4

    companion object {
        val defaultBaseURL = "https://api.groq.com/openai/v1/".toHttpUrl()
        const val transcriptionIdleTimeout = 30.0
        const val polishIdleTimeout = 60.0
        const val keyCheckTimeout = 15.0

        fun transcriptionTimeout(audioSeconds: Double?) =
            maxOf(transcriptionIdleTimeout, 15 + 5 * (audioSeconds ?: 0.0) / 60)

        internal fun parseTranscription(data: String): Transcription {
            val o = parseObject(data)
            val list = o["segments"] as? JsonArray
            val segments =
                list
                    ?.takeIf { it.isNotEmpty() && it.all { item -> item is JsonObject } }
                    ?.map { item ->
                        val s = item.jsonObject
                        WhisperSegment(
                            s.string("text"),
                            s.number("start"),
                            s.number("end"),
                            s.number("avg_logprob"),
                            s.number("no_speech_prob"),
                            s.number("compression_ratio"),
                        )
                    }
            return Transcription(
                o.string("text"),
                o.string("language"),
                o.number("duration"),
                segments,
            )
        }

        fun retryAfter(value: String?, nowMillis: Long = System.currentTimeMillis()): Double? {
            val v = value?.trimmed() ?: return null
            v.toDoubleOrNull()
                ?.takeIf { it.isFinite() && it >= 0 }
                ?.let {
                    return it
                }
            return try {
                maxOf(
                    0.0,
                    (ZonedDateTime.parse(v, DateTimeFormatter.RFC_1123_DATE_TIME)
                        .toInstant()
                        .toEpochMilli() - nowMillis) / 1000.0,
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    fun request(path: String, authenticated: Boolean = true) =
        Request.Builder().url(requireNotNull(baseUrl.resolve(path))).apply {
            if (authenticated) {
                // Reject before OkHttp can throw an IllegalArgumentException containing the key.
                if (apiKey.isEmpty() || apiKey.any { it.code !in 0x21..0x7e })
                    throw GroqFailure(status = 401, code = "unauthorized")
                header("Authorization", "Bearer $apiKey")
            }
        }

    suspend fun <T> send(
        request: Request,
        idleSeconds: Double = polishIdleTimeout,
        parse: (Response) -> T,
    ): T = try {
        currentCoroutineContext().ensureActive()
        // Connectivity snapshots can be stale. Only the HTTP attempt decides success.
        suspendCancellableCoroutine { continuation ->
            val timeout = kotlin.math.ceil(idleSeconds * 1000).toLong()
            val connection = http ?: transport.client()
            val call =
                connection
                    .newBuilder()
                    .readTimeout(timeout, TimeUnit.MILLISECONDS)
                    .writeTimeout(timeout, TimeUnit.MILLISECONDS)
                    .build()
                    .newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(
                object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        if (continuation.isActive) continuation.resumeWithException(GroqFailure())
                    }

                    override fun onResponse(call: Call, response: Response) {
                        try {
                            val result = response.use {
                                if (!it.isSuccessful) {
                                    val error =
                                        try {
                                            parseObject(it.body?.string().orEmpty())["error"]
                                                as? JsonObject
                                        } catch (_: GroqFailure) {
                                            null
                                        }
                                    val wait =
                                        retryAfter(it.header("Retry-After"), clock.nowMillis())
                                            ?: retrySeconds(error?.string("message"))
                                    throw GroqFailure(
                                        it.code,
                                        error?.string("code") ?: "http",
                                        wait,
                                    )
                                }
                                parse(it)
                            }
                            if (continuation.isActive) continuation.resume(result)
                        } catch (e: Throwable) {
                            val failure =
                                when (e) {
                                    is GroqFailure -> e
                                    is IOException -> GroqFailure()
                                    else -> GroqFailure(code = "invalid-response")
                                }
                            if (continuation.isActive) continuation.resumeWithException(failure)
                        }
                    }
                },
            )
        }
    } catch (error: Throwable) {
        throw error.asGroqFailure()
    }

    fun retryDelay(failure: GroqFailure): Double? {
        if (failure.status == 429)
            return (failure.retryAfter ?: 1.0).takeIf { it <= maxRetryAfterSeconds }
        if (failure.status > 0 && failure.retryAfter != null)
            return failure.retryAfter.takeIf { it <= maxRetryAfterSeconds }
        return retryDelaySeconds
    }

    internal suspend fun sendWithRetry(
        request: Request,
        idleSeconds: Double = polishIdleTimeout,
        onAttempt: () -> Unit = {},
    ): String {
        suspend fun attempt(): String {
            onAttempt()
            return send(request, idleSeconds) {
                it.body?.string() ?: throw GroqFailure(code = "invalid-response")
            }
        }
        return try {
            attempt()
        } catch (e: GroqFailure) {
            val wait = retryDelay(e)
            if (!e.retryable || wait == null) throw e
            clock.sleep(wait)
            attempt()
        }
    }

    suspend fun listModels(): List<String> =
        send(request("models").build()) { response ->
            val list =
                parseObject(response.body?.string().orEmpty())["data"] as? JsonArray
                    ?: throw GroqFailure(code = "invalid-response")
            if (list.any { it !is JsonObject }) throw GroqFailure(code = "invalid-response")
            list
                .map { it.jsonObject }
                .filter { (it["active"] as? JsonPrimitive)?.booleanOrNull != false }
                .mapNotNull { it.string("id") }
        }

    internal fun termDiagnostic(requested: Int, accepted: Int) { diagnostic("terms $requested $accepted") }

    @Deprecated("Use listModels or ModelCatalog") suspend fun models() = listModels()

    suspend fun transcribe(
        audio: AudioEncoder.Encoded,
        model: String,
        language: String?,
        prompt: String?,
        audioSeconds: Double? = null,
        bytesSent: (Int) -> Unit = {},
    ): Transcription {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        fun field(name: String, value: String) {
            body.addFormDataPart(
                name,
                null,
                value.toRequestBody("text/plain; charset=utf-8".toMediaType()),
            )
        }
        field("model", model)
        field("response_format", "verbose_json")
        field("temperature", "0")
        language?.trimmed()?.takeIf(String::isNotEmpty)?.let { field("language", it) }
        prompt?.takeIf(String::isNotEmpty)?.let { field("prompt", it) }
        body.addFormDataPart(
            "file",
            audio.fileName,
            audio.data.toRequestBody(audio.mimeType.toMediaType()),
        )
        val request = request("audio/transcriptions").post(body.build()).build()
        val data =
            sendWithRetry(request, transcriptionTimeout(audioSeconds)) {
                diagnostic("whisper.request")
                bytesSent(audio.data.size)
            }
        // Decoding is outside transport retry: malformed successful JSON must not re-upload audio.
        return parseTranscription(data)
    }

    suspend fun chat(
        model: String,
        messages: List<ChatMessage>,
        maxTokens: Int,
        temperature: Double? = 0.0,
    ): ChatCompletion {
        val options = GroqModels.reasoningOptions(model)
        val body = buildJsonObject {
            put("model", model)
            put("max_tokens", maxTokens)
            temperature?.let { put("temperature", it) }
            put("stream", true)
            options.effort?.let { put("reasoning_effort", it) }
            options.format?.let { put("reasoning_format", it) }
            put(
                "messages",
                buildJsonArray {
                    for (m in messages) add(
                        buildJsonObject {
                            put("role", m.role)
                            put("content", m.content)
                        },
                    )
                },
            )
        }
        diagnostic("polish.request")
        return send(
            request("chat/completions")
                .header("Accept", "text/event-stream")
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build(),
        ) { response ->
            val source = response.body?.source() ?: throw GroqFailure(code = "invalid-response")
            val stream = ChatStreamParser()
            // Okio readUtf8Line splits only LF (and strips preceding CR), preserving
            // U+2028/U+2029/NEL.
            while (true) {
                val line = source.readUtf8Line() ?: break
                if (stream.consume(line) == ChatStreamParser.Step.done) break
            }
            stream.completion()
        }
    }

    @Deprecated("Use transcribe(Encoded, model, language, prompt, audioSeconds)")
    suspend fun transcribe(wav: File, durationSeconds: Double): Transcript =
        transcribe(
                AudioEncoder.Encoded(wav.readBytes(), "audio.wav", "audio/wav"),
                GroqModels.whisper,
                null,
                null,
                durationSeconds,
            )
            .legacy()

    @Deprecated("Use chat(model, messages, maxTokens)")
    suspend fun chat(model: String, transcript: Transcript): Completion =
        chat(
                model,
                PolishPrompt.buildMessages(
                    transcript.text,
                    segments = transcript.segments.map { it.core() },
                ),
                GroqModels.polishTokenBudget(transcript.text),
            )
            .let { Completion(it.content.orEmpty(), it.finishReason) }
}

internal fun parseObject(data: String): JsonObject =
    try {
        Json.parseToJsonElement(data) as? JsonObject ?: throw GroqFailure(code = "invalid-response")
    } catch (e: GroqFailure) {
        throw e
    } catch (_: Exception) {
        throw GroqFailure(code = "invalid-response")
    }

internal fun retrySeconds(message: String?): Double? {
    val rest =
        message?.substringAfter("try again in ", "")?.takeIf(String::isNotEmpty) ?: return null
    var seconds = 0.0
    var number = ""
    var found = false
    for (c in rest) {
        if (c.isDigit() || c == '.') number += c
        else {
            val value = number.toDoubleOrNull()
            if (value != null && c in "hms") {
                seconds +=
                    value *
                        when (c) {
                            'h' -> 3600
                            'm' -> 60
                            else -> 1
                        }
                number = ""
                found = true
                if (c == 's') break
            } else break
        }
    }
    return if (found) seconds else null
}

/** Preserve structured cancellation, but classify every other failure without retaining secrets. */
internal suspend fun Throwable.asGroqFailure(): GroqFailure {
    currentCoroutineContext().ensureActive()
    return this as? GroqFailure ?: GroqFailure()
}

/** Clean pasted keys before saving them in app settings (never silently mutate a request key). */
fun sanitizeApiKey(value: String): String = buildString {
    for (code in value.scalars()) {
        if (!code.isUnicodeWhitespace() && !Character.isISOControl(code) &&
            Character.getType(code) != Character.FORMAT.toInt() &&
            code != 0x034f && code !in 0xfe00..0xfe0f && code !in 0xe0100..0xe01ef
        ) appendCodePoint(code)
    }
}
