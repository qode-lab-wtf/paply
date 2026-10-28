package com.paply.core

import java.security.MessageDigest
import kotlinx.coroutines.*

/**
 * Five-minute, per-key memory cache. Only the SHA-256 prefix is stored as key. cachedModels starts
 * a shared background refresh and NEVER waits, even on a cold cache. models is the explicit
 * warming/testing API which can await the first/forced fetch.
 */
class ModelCatalog(private val clock: PaplyClock = SystemPaplyClock) : AutoCloseable {
    companion object {
        const val lifetime = 300.0
        val shared = ModelCatalog()

        fun fingerprint(apiKey: String) =
            MessageDigest.getInstance("SHA-256")
                .digest(apiKey.toByteArray(Charsets.UTF_8))
                .take(12)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private data class Entry(val ids: List<String>, val checkedAt: Long)

    private val entries = mutableMapOf<String, Entry>()
    private val pending = mutableMapOf<String, Deferred<List<String>?>>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var generation = 0L

    @Synchronized
    fun cachedModels(client: GroqClient): List<String>? {
        val key = fingerprint(client.apiKey)
        val entry = entries[key]
        if (entry == null || (clock.nowMillis() - entry.checkedAt) / 1000.0 >= lifetime)
            fetch(key, client)
        return entry?.ids
    }

    suspend fun models(client: GroqClient, forceRefresh: Boolean = false): List<String>? {
        val task =
            synchronized(this) {
                val key = fingerprint(client.apiKey)
                val entry = entries[key]
                if (!forceRefresh && entry != null) {
                    if ((clock.nowMillis() - entry.checkedAt) / 1000.0 >= lifetime)
                        fetch(key, client)
                    return entry.ids
                }
                fetch(key, client)
            }
        return task.await() // Cancelling a waiter does not cancel the shared fetch.
    }

    @Synchronized
    private fun fetch(key: String, client: GroqClient): Deferred<List<String>?> {
        pending[key]?.let {
            return it
        }
        val epoch = generation
        val task =
            scope.async(start = CoroutineStart.LAZY) {
                val ids =
                    try {
                        client.listModels()
                    } catch (_: GroqFailure) {
                        null
                    }
                synchronized(this@ModelCatalog) {
                    if (generation == epoch) {
                        pending.remove(key)
                        if (ids != null) entries[key] = Entry(ids.toList(), clock.nowMillis())
                    }
                }
                ids
            }
        pending[key] = task
        task.start()
        return task
    }

    @Synchronized
    fun age(apiKey: String): Double? =
        entries[fingerprint(apiKey)]?.let { (clock.nowMillis() - it.checkedAt) / 1000.0 }

    @Synchronized
    fun remove(model: String, apiKey: String) {
        val key = fingerprint(apiKey)
        entries[key]?.let { entries[key] = it.copy(ids = it.ids.filter { id -> id != model }) }
    }

    @Synchronized
    fun reset() {
        generation++
        entries.clear()
        pending.clear()
    }

    override fun close() {
        reset()
        scope.cancel()
    }
}

data class PolishResult(
    val polished: String? = null,
    val rejection: String? = null,
    val error: PolishFailureCode? = null,
    val model: String? = null,
)

class PolishService(
    private val client: GroqClient,
    private val catalog: ModelCatalog = ModelCatalog.shared,
    private val strictEdits: Boolean = true,
) {
    suspend fun polish(
        text: String,
        messages: List<ChatMessage>,
        vocabulary: String,
        settings: PaplySettings,
    ): PolishResult {
        val preferred =
            listOf(settings.polishModel, settings.fallbackPolishModel)
                .filter(String::isNotEmpty)
                .distinct()
        if (preferred.isEmpty()) return PolishResult(error = PolishFailureCode.modelUnavailable)
        // Explicit Android requirement: even the first catalogue fetch never gates polishing.
        val available = catalog.cachedModels(client)
        currentCoroutineContext().ensureActive()
        var model =
            (if (available != null) GroqModels.select(available, preferred) else preferred.first())
                ?: return PolishResult(error = PolishFailureCode.modelUnavailable)
        val maxTokens = GroqModels.polishTokenBudget(text)
        val completion =
            try {
                try {
                    client.chat(model, messages, maxTokens)
                } catch (failure: GroqFailure) {
                    val fallback = preferred.firstOrNull {
                        it != model && (available == null || it in available)
                    }
                    val wait = client.retryDelay(failure)
                    if (failure.modelMissing) {
                        catalog.remove(model, client.apiKey)
                        if (fallback == null)
                            return PolishResult(
                                error = PolishFailureCode.modelUnavailable,
                                model = model,
                            )
                        model = fallback
                    } else if (failure.status == 429 && wait == null && fallback != null)
                        model = fallback
                    else if (failure.retryable && wait != null) client.clock.sleep(wait)
                    else throw failure
                    client.chat(model, messages, maxTokens)
                }
            } catch (failure: GroqFailure) {
                return PolishResult(error = failure.polishCode, model = model)
            }
        if (completion.finishReason != null && completion.finishReason != "stop")
            return PolishResult(rejection = "truncated", model = model)
        val result = PolishSafetyNet.finalPolishText(completion.content?.trimmed())
        val rejection = PolishSafetyNet.rejection(text, result, vocabulary, strictEdits)
        return if (rejection != null) PolishResult(rejection = rejection, model = model)
        else PolishResult(polished = result, model = model)
    }
}
