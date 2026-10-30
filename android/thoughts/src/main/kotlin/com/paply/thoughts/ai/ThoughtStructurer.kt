package com.paply.thoughts.ai

import com.paply.core.*
import com.paply.thoughts.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.processing.ThoughtTrace
import com.paply.thoughts.processing.ThoughtTrace.Value.*
import java.time.Instant
import kotlinx.coroutines.*
import okhttp3.HttpUrl

class ThoughtStructurer(
    private val ledger: TokenLedger? = null,
    private val transport: GroqTransport = GroqTransport.shared,
    private val baseURL: HttpUrl = GroqClient.defaultBaseURL,
    private val selfID: String? = null,
    private val models: () -> Models = { Models.standard },
    private val now: () -> Instant = Instant::now,
    private val trace: ThoughtTrace = ThoughtTrace.off,
    private val sleep: suspend (Double) -> Unit = { delay((it * 1000).toLong().coerceAtLeast(0)) },
) : ThoughtStructuring {
    data class Models(val primary: String, val fallback: String?) {
        companion object {
            val standard = Models(primaryModel, fallbackModel)
        }
    }

    companion object {
        const val primaryModel = "openai/gpt-oss-120b"
        const val fallbackModel = "openai/gpt-oss-20b"
        const val limitWait = 900.0
    }

    override suspend fun structure(input: StructureInput, apiKey: String): StructureOutcome {
        val key = TextForm.trim(apiKey)
        if (key.isEmpty())
            return StructureOutcome.Wait(ThoughtState.waitingKey, null, "Groq-Schlüssel fehlt")
        val built =
            try {
                ThoughtPrompt.build(input, now = input.recordedAt ?: now())
            } catch (_: ThoughtPrompt.BuildError) {
                return StructureOutcome.Unusable("too_large")
            }
        val client = GroqClient(key, baseUrl = baseURL, transport = transport)
        val chosen = models()
        val fallback = chosen.fallback?.takeIf { it.isNotEmpty() && it != chosen.primary }
        var model = chosen.primary
        var effort = input.reasoningEffort
        var usedShortRetry = false
        var usedFallback = false
        var usedEffortRetry = false
        var usage = TokenUsage(0, 0, 0)
        val thoughtID = currentCoroutineContext()[ThoughtTrace.ThoughtID]?.id
        fun retryWithMoreReasoning(): Boolean {
            if (usedEffortRetry) return false
            usedEffortRetry = true
            effort = "medium"
            return true
        }
        fun report(
            status: String,
            started: Long,
            response: StructuredChatResponse? = null,
            failure: GroqFailure? = null,
            valid: Boolean? = null,
            codes: List<String> = emptyList(),
            next: String,
        ) {
            val fields =
                mutableMapOf<String, ThoughtTrace.Value>(
                    "model" to S(model),
                    "effort" to S(effort),
                    "part" to I(input.part?.index ?: 0),
                    "status" to S(status),
                    "ms" to ThoughtTrace.milliseconds(started),
                    "estimate" to I(built.estimate),
                    "next" to S(next),
                )
            thoughtID?.let { fields["id"] = S(it) }
            // Never log arbitrary error-code/finish strings from an untrusted server.
            failure
                ?.code
                ?.takeIf {
                    it in
                        setOf(
                            "json_validate_failed",
                            "rate_limit_exceeded",
                            "model_decommissioned",
                            "model_not_found",
                            "invalid_api_key",
                            "unauthorized",
                            "http",
                        )
                }
                ?.let { fields["groqCode"] = S(it) }
            response
                ?.finishReason
                ?.takeIf {
                    it in setOf("stop", "length", "content_filter", "tool_calls", "function_call")
                }
                ?.let { fields["finish"] = S(it) }
            response?.usage?.let {
                fields["tokens"] = I(it.total)
                fields["promptTokens"] = I(it.prompt)
                fields["completionTokens"] = I(it.completion)
            }
            failure?.retryAfter?.let { fields["retryAfterS"] = ThoughtTrace.Value.ms(it) }
            valid?.let { fields["valid"] = B(it) }
            if (codes.isNotEmpty()) fields["codes"] = S(codes.joinToString(","))
            trace.log("thought.groq", fields)
        }
        while (true) {
            if (!currentCoroutineContext().isActive)
                return StructureOutcome.Wait(ThoughtState.waitingNetwork, null, "Abgebrochen")
            val reservation =
                try {
                    ledger?.reserve(model, built.estimate, TokenLedger.Unit.tokens)
                } catch (e: TokenLedger.Refusal) {
                    val retryAt =
                        when (e) {
                            is TokenLedger.Refusal.Budget -> e.retryAt
                            is TokenLedger.Refusal.Minute -> e.retryAt
                            else -> null
                        }
                    val reason =
                        when (e) {
                            is TokenLedger.Refusal.Budget -> "budget"
                            is TokenLedger.Refusal.Minute -> "minute"
                            else -> "tooSmall"
                        }
                    val f =
                        mutableMapOf<String, ThoughtTrace.Value>(
                            "model" to S(model),
                            "reason" to S(reason),
                        )
                    thoughtID?.let { f["id"] = S(it) }
                    retryAt?.let {
                        f["waitS"] =
                            ThoughtTrace.Value.ms(
                                maxOf(0.0, (it.toEpochMilli() - now().toEpochMilli()) / 1000.0),
                            )
                    }
                    trace.log("thought.groq.ledger", f)
                    return if (e == TokenLedger.Refusal.BudgetTooSmall)
                        StructureOutcome.Unusable("budget_small")
                    else
                        StructureOutcome.Wait(
                            ThoughtState.waitingBudget,
                            retryAt,
                            if (e is TokenLedger.Refusal.Budget)
                                "Gedanken-Budget für heute erreicht"
                            else "Kurze Pause für das Groq-Limit",
                        )
                }
            val request =
                StructuredChatRequest(
                    model,
                    built.system,
                    built.user,
                    if (built.isPart) ThoughtSchema.partName else ThoughtSchema.name,
                    ThoughtSchema.data(
                        if (built.isPart) ThoughtSchema.part else ThoughtSchema.full,
                    ),
                    built.maxCompletionTokens,
                    effort,
                )
            val start = System.nanoTime()
            try {
                val response = client.chatStructured(request)
                reservation?.let { ledger?.settle(it, response.usage?.total) }
                response.usage?.let {
                    usage =
                        TokenUsage(
                            usage.prompt + it.prompt,
                            usage.completion + it.completion,
                            usage.total + it.total,
                        )
                }
                if (response.finishReason != "stop" || response.content == null) {
                    report("ok", start, response, next = if (usedEffortRetry) "raw" else "medium")
                    if (retryWithMoreReasoning()) continue
                    return StructureOutcome.Unusable("invalid_output")
                }
                val result =
                    if (built.isPart) ThoughtValidator.validatePart(response.content, input)
                    else ThoughtValidator.validate(response.content, input, built.aliases, selfID)
                val value = result.getOrNull()
                if (value != null) {
                    report(
                        "ok",
                        start,
                        response,
                        valid = true,
                        codes = value.rejections,
                        next = "done",
                    )
                    return StructureOutcome.Success(value, model, usage)
                }
                report(
                    "ok",
                    start,
                    response,
                    valid = false,
                    next = if (usedEffortRetry) "raw" else "medium",
                )
                if (retryWithMoreReasoning()) continue
                return StructureOutcome.Unusable("invalid_output")
            } catch (e: CancellationException) {
                reservation?.let { ledger?.settle(it, null) }
                return StructureOutcome.Wait(ThoughtState.waitingNetwork, null, "Abgebrochen")
            } catch (e: GroqFailure) {
                reservation?.let {
                    ledger?.settle(it, if (e.status in listOf(401, 403, 404, 429)) 0 else null)
                }
                fun failed(next: String) =
                    report(
                        if (e.status > 0) "http-${e.status}" else e.code,
                        start,
                        failure = e,
                        next = next,
                    )
                when {
                    (e.status == 400 && e.code == "json_validate_failed") ||
                        e.code == "invalid-response" -> {
                        failed(if (usedEffortRetry) "raw" else "medium")
                        if (retryWithMoreReasoning()) continue
                        return StructureOutcome.Unusable("invalid_output")
                    }
                    e.status == 429 -> {
                        val wait = e.retryAfter
                        if (
                            wait != null && wait <= client.maxRetryAfterSeconds && !usedShortRetry
                        ) {
                            usedShortRetry = true
                            failed("retry")
                            try {
                                sleep(wait)
                            } catch (_: CancellationException) {
                                return StructureOutcome.Wait(
                                    ThoughtState.waitingNetwork,
                                    null,
                                    "Abgebrochen",
                                )
                            }
                            continue
                        }
                        if (fallback != null && !usedFallback) {
                            usedFallback = true
                            failed("fallback")
                            model = fallback
                            continue
                        }
                        failed("wait")
                        return StructureOutcome.Wait(
                            ThoughtState.waitingLimit,
                            now().plusMillis((maxOf(wait ?: 0.0, limitWait) * 1000).toLong()),
                            "Groq-Limit · später erneut",
                        )
                    }
                    e.status == 401 || e.status == 403 -> {
                        failed("waitKey")
                        return StructureOutcome.Wait(
                            ThoughtState.waitingKey,
                            null,
                            "Groq-Schlüssel prüfen",
                        )
                    }
                    e.modelMissing -> {
                        if (fallback != null && !usedFallback) {
                            usedFallback = true
                            failed("fallback")
                            model = fallback
                            continue
                        }
                        failed("raw")
                        return StructureOutcome.Unusable("model_missing")
                    }
                    e.status >= 500 -> {
                        failed("wait")
                        return StructureOutcome.Wait(
                            ThoughtState.waitingNetwork,
                            null,
                            "Groq ist gerade gestört",
                        )
                    }
                    e.status > 0 -> {
                        failed("raw")
                        return StructureOutcome.Unusable("request_rejected")
                    }
                    else -> {
                        failed("wait")
                        return StructureOutcome.Wait(
                            ThoughtState.waitingNetwork,
                            null,
                            if (e.code == "cancelled") "Abgebrochen" else "Wartet auf Netz",
                        )
                    }
                }
            }
        }
    }
}
