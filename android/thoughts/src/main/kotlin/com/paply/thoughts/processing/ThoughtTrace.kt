package com.paply.thoughts.processing

import com.paply.thoughts.model.TextForm
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/** Sink accepts fixed event codes, short IDs and numeric metadata, never thought contents. */
class ThoughtTrace(private val sink: ((String, Map<String, Value>) -> Unit)? = null) {
    sealed interface Value {
        data class S(val value: String) : Value

        data class I(val value: Int) : Value

        data class D(val value: Double) : Value

        data class B(val value: Boolean) : Value

        companion object {
            fun ms(value: Double) =
                D(
                    java.math.BigDecimal.valueOf(value)
                        .setScale(1, java.math.RoundingMode.HALF_UP)
                        .toDouble(),
                )
        }
    }

    class ThoughtID(val id: String) : AbstractCoroutineContextElement(Key) {
        companion object Key : CoroutineContext.Key<ThoughtID>
    }

    fun log(event: String, fields: Map<String, Value>) {
        sink?.invoke(event, fields)
    }

    companion object {
        val off = ThoughtTrace()

        fun short(id: String) = TextForm.prefix(id, 10)

        fun milliseconds(since: Long) = Value.ms((System.nanoTime() - since) / 1e6)
    }
}
