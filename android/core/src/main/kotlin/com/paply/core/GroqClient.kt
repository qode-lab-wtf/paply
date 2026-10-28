package com.paply.core

import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody

/** Contains only safe classifications, never remote messages, credentials or dictated text. */
class GroqFailure(val status: Int = 0, val code: String = "network", val retryAfter: Double? = null) :
    IOException(if (status == 0) code else "http-$status") {
    val modelMissing get() = status == 404 || (status == 400 && code in listOf("model_decommissioned", "model_not_found"))
    val retryable get() = status == 0 || status in listOf(408, 409, 429) || status >= 500
    fun retryDelay(): Long? {
        val seconds = retryAfter ?: if (status == 429) 1.0 else 0.4
        return if (seconds <= 20) (seconds * 1000).toLong().coerceAtLeast(0) else null
    }
}

data class Segment(val text: String, val start: Double?, val end: Double?, val logprob: Double?)
data class Transcript(val text: String, val language: String?, val segments: List<Segment>)
data class Completion(val text: String, val finishReason: String?)
data class DictationResult(val raw: String, val text: String, val model: String?, val fallbackReason: String?)

object GroqModels {
    const val whisper = "whisper-large-v3"
    const val polish = "qwen/qwen3.8-27b"
    const val polishFallback = "openai/gpt-oss-120b"
    fun tokenBudget(text: String) = (kotlin.math.ceil(text.length / 3.0).toInt() * 2).coerceIn(4096, 32768)
}

class GroqClient(
    private val apiKey: String,
    private val baseUrl: HttpUrl = HttpUrl.Builder().scheme("https").host("api.groq.com").addPathSegments("openai/v1/").build(),
    private val http: OkHttpClient = sharedHttp,
    private val diagnostic: (String) -> Unit = {},
) {
    companion object {
        // A read timeout detects a dead stream. There is deliberately no overall polish deadline.
        private val sharedHttp = OkHttpClient.Builder().callTimeout(0, TimeUnit.MILLISECONDS)
            .readTimeout(60, TimeUnit.SECONDS).connectTimeout(20, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false).followRedirects(false).build()
    }
    private fun request(path: String) = Request.Builder().url(requireNotNull(baseUrl.resolve(path)))
        .header("Authorization", "Bearer $apiKey")

    private suspend fun <T> send(request: Request, idleSeconds: Long = 60, parse: (Response) -> T): T =
        suspendCancellableCoroutine { continuation ->
            val call = http.newBuilder().readTimeout(idleSeconds, TimeUnit.SECONDS).build().newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(GroqFailure())
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val result = response.use {
                            if (!it.isSuccessful) {
                                val error = runCatching { Json.parseToJsonElement(it.body!!.string()).jsonObject["error"]?.jsonObject }.getOrNull()
                                // Error text is parsed only for retry timing and is never retained/logged.
                                val wait = it.header("Retry-After")?.toDoubleOrNull()
                                    ?: retrySeconds(error?.get("message")?.jsonPrimitive?.contentOrNull)
                                throw GroqFailure(it.code, error?.get("code")?.jsonPrimitive?.contentOrNull ?: "http", wait)
                            }
                            parse(it)
                        }
                        if (continuation.isActive) continuation.resume(result)
                    } catch (e: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(if (e is GroqFailure) e else GroqFailure(code = "invalid-response"))
                    }
                }
            })
        }

    suspend fun models(): List<String> = send(request("models").build(), 15) { response ->
        Json.parseToJsonElement(response.body!!.string()).jsonObject.getValue("data").jsonArray
            .filter { it.jsonObject["active"]?.jsonPrimitive?.booleanOrNull != false }
            .map { it.jsonObject.getValue("id").jsonPrimitive.content }
    }

    suspend fun transcribe(wav: File, durationSeconds: Double): Transcript {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("model", GroqModels.whisper).addFormDataPart("response_format", "verbose_json")
            .addFormDataPart("temperature", "0")
            // Empty vocabulary, no previous chunk: iOS WhisperPrompt.build returns nil.
            .addFormDataPart("file", "recording.wav", wav.asRequestBody("audio/wav".toMediaType())).build()
        val request = request("audio/transcriptions").post(body).build()
        suspend fun attempt(): Transcript {
            diagnostic("whisper.request")
            return send(request, maxOf(30L, (15 + 5 * durationSeconds / 60).toLong())) {
                val obj = Json.parseToJsonElement(it.body!!.string()).jsonObject
                Transcript(obj.getValue("text").jsonPrimitive.content.trim(), obj["language"]?.jsonPrimitive?.contentOrNull,
                    obj["segments"]?.jsonArray?.map { item ->
                        val s = item.jsonObject
                        Segment(s["text"]?.jsonPrimitive?.contentOrNull.orEmpty(), s["start"]?.jsonPrimitive?.doubleOrNull,
                            s["end"]?.jsonPrimitive?.doubleOrNull, s["avg_logprob"]?.jsonPrimitive?.doubleOrNull)
                    }.orEmpty())
            }
        }
        return try { attempt() } catch (e: GroqFailure) {
            val wait = e.retryDelay()
            if (!e.retryable || wait == null) throw e
            delay(wait); attempt()
        }
    }

    suspend fun chat(model: String, transcript: Transcript): Completion {
        val payload = buildJsonObject {
            put("background_do_not_edit", JsonArray(emptyList()))
            put("current_dictation", transcript.text)
            put("uncertain_segments", buildJsonArray {
                transcript.segments.filter { it.logprob?.let { p -> p.isFinite() && p < -0.5 } == true }.forEach { s ->
                    add(buildJsonObject {
                        put("text", s.text); s.start?.let { put("start", it) }; s.end?.let { put("end", it) }
                        put("avg_logprob", s.logprob!!)
                    })
                }
            })
        }
        val body = buildJsonObject {
            put("model", model); put("max_tokens", GroqModels.tokenBudget(transcript.text)); put("temperature", 0)
            put("stream", true)
            if (model.startsWith("qwen/")) put("reasoning_effort", "none")
            if (model.startsWith("openai/gpt-oss-")) { put("reasoning_format", "hidden"); put("reasoning_effort", "low") }
            put("messages", buildJsonArray {
                add(buildJsonObject { put("role", "system"); put("content", PolishPrompt.systemPrompt) })
                add(buildJsonObject { put("role", "user"); put("content", payload.toString()) })
            })
        }
        diagnostic("polish.request")
        return send(request("chat/completions").header("Accept", "text/event-stream")
            .post(body.toString().toRequestBody("application/json".toMediaType())).build()) { response ->
            val source = response.body!!.source()
            val content = StringBuilder()
            val plain = StringBuilder()
            var reason: String? = null
            var event = false
            var done = false
            while (!source.exhausted()) {
                val line = source.readUtf8Line() ?: break
                if (!line.startsWith("data:")) {
                    if (!event && !line.startsWith(":")) plain.append(line)
                    continue
                }
                event = true
                val data = line.removePrefix("data:").trim()
                if (data == "[DONE]") { done = true; break }
                val obj = Json.parseToJsonElement(data).jsonObject
                if (obj["error"] != null) throw GroqFailure(code = "stream-error")
                val choice = obj["choices"]?.jsonArray?.firstOrNull()?.jsonObject ?: continue
                choice["delta"]?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull?.let(content::append)
                choice["finish_reason"]?.jsonPrimitive?.contentOrNull?.let { reason = it }
            }
            if (event) {
                if (!done && reason == null) throw GroqFailure(code = "incomplete-stream")
                Completion(content.toString(), reason)
            } else {
                val choice = Json.parseToJsonElement(plain.toString()).jsonObject.getValue("choices").jsonArray.first().jsonObject
                Completion(choice["message"]?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull.orEmpty(),
                    choice["finish_reason"]?.jsonPrimitive?.contentOrNull)
            }
        }
    }
}

internal fun retrySeconds(message: String?): Double? {
    val tail = message?.substringAfter("try again in ", "")?.takeIf { it.isNotEmpty() } ?: return null
    val parts = Regex("([0-9]+(?:\\.[0-9]+)?)([hms])").findAll(tail).toList()
    return parts.takeIf { it.isNotEmpty() }?.sumOf { it.groupValues[1].toDouble() * when(it.groupValues[2]) { "h" -> 3600; "m" -> 60; else -> 1 } }
}

/** Phase-0 pipeline: batch WAV -> raw transcript -> a complete polish, or a genuine error. */
class DictationPipeline(private val client: GroqClient) {
    suspend fun dictate(wav: File, seconds: Double): DictationResult = polish(client.transcribe(wav, seconds))
    suspend fun polish(raw: Transcript): DictationResult {
        if (raw.text.isBlank()) return DictationResult("", "", null, null)
        val preferred = listOf(GroqModels.polish, GroqModels.polishFallback)
        val available = try { client.models() } catch (e: GroqFailure) { null }
        var model = preferred.firstOrNull { available == null || it in available }
            ?: return DictationResult(raw.text, raw.text, null, "model-unavailable")
        try {
            val completion = try { client.chat(model, raw) } catch (e: GroqFailure) {
                val fallback = preferred.firstOrNull { it != model && (available == null || it in available) }
                val wait = e.retryDelay()
                if ((e.modelMissing || (e.status == 429 && wait == null)) && fallback != null) {
                    model = fallback
                } else if (e.retryable && wait != null) { delay(wait) } else throw e
                client.chat(model, raw)
            }
            if (completion.finishReason != null && completion.finishReason != "stop") throw GroqFailure(code = "truncated")
            if (completion.text.isBlank()) throw GroqFailure(code = "empty-polish")
            return DictationResult(raw.text, completion.text.trim(), model, null)
        } catch (e: CancellationException) { throw e
        } catch (e: GroqFailure) { return DictationResult(raw.text, raw.text, model, e.message) }
    }
}
