package com.paply.core

sealed interface KeyCheck {
    data object Valid : KeyCheck

    data object Invalid : KeyCheck

    data object Offline : KeyCheck

    data class Failed(val message: String) : KeyCheck
}

object GroqConnection {
    const val modelListMaxAge = 6 * 60 * 60.0

    suspend fun prewarm(apiKey: String, refreshModels: Boolean = false) {
        if (apiKey.trimmed().isNotEmpty())
            prewarm(GroqClient(apiKey), ModelCatalog.shared, refreshModels)
    }

    suspend fun prewarm(client: GroqClient, catalog: ModelCatalog, refreshModels: Boolean = false) {
        if (client.apiKey.trimmed().isEmpty()) return
        val age = catalog.age(client.apiKey)
        try {
            if (refreshModels || age == null || age > modelListMaxAge)
                catalog.models(client, forceRefresh = true)
            else
                client.send(
                    client.request("models", authenticated = false).head().build(),
                    GroqClient.keyCheckTimeout,
                ) {
                    Unit
                }
        } catch (_: GroqFailure) {
            /* warming is best effort */
        }
    }

    suspend fun validate(apiKey: String) = checkKey(apiKey) == KeyCheck.Valid

    suspend fun checkKey(apiKey: String) = checkKey(GroqClient(apiKey.trimmed()))

    suspend fun checkKey(client: GroqClient): KeyCheck {
        if (client.apiKey.isEmpty()) return KeyCheck.Invalid
        // Separate retry policy without mutating a client shared with dictation.
        suspend fun attempt() {
            client.send(client.request("models").build(), GroqClient.keyCheckTimeout) {
                it.body?.bytes()
                Unit
            }
        }
        return try {
            try {
                attempt()
            } catch (f: GroqFailure) {
                val wait =
                    if (f.status == 429) f.retryAfter ?: 1.0
                    else f.retryAfter ?: client.retryDelaySeconds
                val allowed =
                    if (f.status > 0 && (f.retryAfter != null || f.status == 429)) wait <= 0
                    else true
                if (!f.retryable || !allowed) throw f
                client.clock.sleep(wait)
                attempt()
            }
            KeyCheck.Valid
        } catch (f: GroqFailure) {
            when {
                f.status == 429 -> KeyCheck.Valid
                f.status == 401 || f.status == 403 -> KeyCheck.Invalid
                f.status == 0 && f.code == "network" -> KeyCheck.Offline
                f.status in 1..499 ->
                    KeyCheck.Failed(
                        "Schlüsselprüfung fehlgeschlagen (Fehler ${f.status}) – bitte später erneut versuchen.",
                    )
                else -> KeyCheck.Failed(f.germanMessage)
            }
        }
    }

    fun reset() {
        GroqTransport.shared.reset()
        ModelCatalog.shared.reset()
    }
}
