package com.paply.thoughts.ai

import com.paply.core.GroqClient
import com.paply.core.GroqFailure
import com.paply.thoughts.TokenUsage
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

data class StructuredChatRequest(
    val model: String,
    val system: String,
    val user: String,
    val schemaName: String,
    val schema: ByteArray,
    val maxCompletionTokens: Int,
    val reasoningEffort: String = "low",
    val temperature: Double = 0.1,
)

data class StructuredChatResponse(
    val content: String?,
    val finishReason: String?,
    val usage: TokenUsage?,
)

const val structuredIdleTimeout = 120.0

/** One HTTP attempt. Retry, model fallback and accounting belong to ThoughtStructurer. */
suspend fun GroqClient.chatStructured(request: StructuredChatRequest): StructuredChatResponse {
    val schema = runCatching {
        Json.parseToJsonElement(request.schema.toString(Charsets.UTF_8))
    }
        .getOrElse { throw GroqFailure(code = "invalid-response") }
    val body = buildJsonObject {
        put("model", request.model)
        put("temperature", request.temperature)
        put("reasoning_effort", request.reasoningEffort)
        put("max_completion_tokens", request.maxCompletionTokens)
        putJsonArray("messages") {
            add(
                buildJsonObject {
                    put("role", "system")
                    put("content", request.system)
                },
            )
            add(
                buildJsonObject {
                    put("role", "user")
                    put("content", request.user)
                },
            )
        }
        putJsonObject("response_format") {
            put("type", "json_schema")
            putJsonObject("json_schema") {
                put("name", request.schemaName)
                put("strict", true)
                put("schema", schema)
            }
        }
    }
    return send(
        request("chat/completions")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build(),
        structuredIdleTimeout,
    ) { response ->
        val o = Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject
        val c =
            (o["choices"] as? JsonArray)?.firstOrNull() as? JsonObject
                ?: throw GroqFailure(code = "invalid-response")
        fun JsonObject.string(k: String) =
            (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
        val u = o["usage"] as? JsonObject
        val total = (u?.get("total_tokens") as? JsonPrimitive)?.intOrNull
        StructuredChatResponse(
            (c["message"] as? JsonObject)?.string("content"),
            c.string("finish_reason"),
            total?.let {
                TokenUsage(
                    (u["prompt_tokens"] as? JsonPrimitive)?.intOrNull ?: 0,
                    (u["completion_tokens"] as? JsonPrimitive)?.intOrNull ?: 0,
                    it,
                )
            },
        )
    }
}
