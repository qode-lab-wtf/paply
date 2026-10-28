package com.paply.thoughts.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*
import kotlinx.serialization.json.*

object InstantMillisSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("UnixMilliseconds", PrimitiveKind.LONG)

    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeLong(ThoughtJSON.milliseconds(value))

    override fun deserialize(decoder: Decoder): Instant {
        val n =
            if (decoder is JsonDecoder)
                decoder.decodeJsonElement().jsonPrimitive.content.toBigDecimal()
            else BigDecimal.valueOf(decoder.decodeDouble())
        val nanos = n.multiply(BigDecimal(1_000_000)).toBigInteger()
        return Instant.ofEpochSecond(
            nanos.divide(java.math.BigInteger.valueOf(1_000_000_000)).toLong(),
            nanos.remainder(java.math.BigInteger.valueOf(1_000_000_000)).toLong(),
        )
    }
}

object ThoughtJSON {
    val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    fun milliseconds(date: Instant): Long =
        BigDecimal.valueOf(date.epochSecond)
            .multiply(BigDecimal(1000))
            .add(BigDecimal.valueOf(date.nano.toLong(), 6))
            .setScale(0, RoundingMode.HALF_UP)
            .longValueExact()

    fun sorted(element: JsonElement): JsonElement =
        when (element) {
            is JsonObject -> JsonObject(element.toSortedMap().mapValues { sorted(it.value) })
            is JsonArray -> JsonArray(element.map(::sorted))
            else -> element
        }

    inline fun <reified T> encode(value: T): ByteArray =
        sorted(json.encodeToJsonElement(value)).toString().toByteArray(Charsets.UTF_8)

    inline fun <reified T> decode(data: ByteArray): T =
        json.decodeFromString(data.toString(Charsets.UTF_8))
}

/** A separate 256-element drop-oldest channel per subscriber, like the Swift Broadcast. */
class Broadcast<T> {
    private val channels = mutableSetOf<Channel<T>>()
    private var finished = false
    val stream: Flow<T>
        get() {
            val channel = Channel<T>(256, kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST)
            synchronized(this) { if (finished) channel.close() else channels.add(channel) }
            return flow {
                try {
                    for (item in channel) emit(item)
                } finally {
                    synchronized(this@Broadcast) { channels.remove(channel) }
                    channel.cancel()
                }
            }
        }

    @Synchronized
    fun yield(element: T) {
        channels.forEach { it.trySend(element) }
    }

    @Synchronized
    fun finish() {
        finished = true
        channels.forEach { it.close() }
        channels.clear()
    }
}

object StableHash {
    fun of(text: String): ULong {
        var hash = 0xcbf29ce484222325uL
        for (b in text.toByteArray(Charsets.UTF_8)) {
            hash = (hash xor b.toUByte().toULong()) * 0x100000001b3uL
        }
        return hash
    }
}

object Parallel {
    fun <T> map(count: Int, transform: (Int) -> T?): List<T?> =
        if (count <= 0) emptyList()
        else java.util.stream.IntStream.range(0, count).parallel().mapToObj(transform).toList()
}

object TextForm {
    private val graphemes = Regex("\\X")

    fun characters(text: String) = graphemes.findAll(text).map { it.value }.toList()

    fun count(text: String) = graphemes.findAll(text).count()

    fun prefix(text: String, count: Int) =
        graphemes.findAll(text).take(count.coerceAtLeast(0)).joinToString("") { it.value }

    fun trim(text: String) = text.trim { it.isWhitespace() || it == '\u0085' || it == '\u200b' }

    fun words(text: String) = text.split(Regex("[\\s\\p{Z}\\u0085]+")).filter { it.isNotEmpty() }
}
