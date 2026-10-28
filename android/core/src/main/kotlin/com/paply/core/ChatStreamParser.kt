package com.paply.core

import kotlinx.serialization.json.*

internal class ChatStreamParser {
    enum class Step {
        more,
        done,
    }

    private val content = StringBuilder()
    private var finishReason: String? = null
    private var sawEvent = false
    private var sawDone = false
    private var failure: GroqFailure? = null
    private val plain = StringBuilder()

    companion object {
        fun decodeLine(data: ByteArray) = data.toString(Charsets.UTF_8).removeSuffix("\r")

        fun failure(error: JsonObject): GroqFailure {
            val code = error.string("code")
            return if (
                code == "rate_limit_exceeded" ||
                    error.string("type")?.contains("rate_limit") == true
            )
                GroqFailure(429, code ?: "http", retrySeconds(error.string("message")))
            else GroqFailure(code = "invalid-response")
        }
    }

    fun consume(line: String): Step {
        if (!line.startsWith("data:")) {
            plain.append(line).append('\n')
            return Step.more
        }
        val payload = line.substring(5).trim { it.code.isFoundationSpace() }
        if (payload == "[DONE]") {
            sawDone = true
            return Step.done
        }
        sawEvent = true
        val obj =
            try {
                parseObject(payload)
            } catch (e: GroqFailure) {
                failure = e
                return Step.done
            }
        (obj["error"] as? JsonObject)?.let {
            failure = failure(it)
            return Step.done
        }
        val choice = (obj["choices"] as? JsonArray)?.firstOrNull() as? JsonObject
        (choice?.get("delta") as? JsonObject)?.string("content")?.let(content::append)
        choice?.string("finish_reason")?.let { finishReason = it }
        return Step.more
    }

    fun completion(): ChatCompletion {
        failure?.let { throw it }
        if (sawEvent) {
            if (!sawDone && finishReason == null) throw GroqFailure(code = "invalid-response")
            return ChatCompletion(content.toString(), finishReason)
        }
        val obj = parseObject(plain.toString())
        val first =
            (obj["choices"] as? JsonArray)?.firstOrNull() as? JsonObject
                ?: throw GroqFailure(code = "invalid-response")
        return ChatCompletion(
            (first["message"] as? JsonObject)?.string("content"),
            first.string("finish_reason"),
        )
    }
}
