package com.paply.thoughts.display

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*
import kotlinx.serialization.json.*

/**
 * Shared/Core snapshots and snoozes use JSONEncoder's default: seconds since 2001, including
 * fractions. ThoughtJSON's millisecond rounding would lose completion/snapshot precision here.
 */
object FoundationDateSerializer : KSerializer<Instant> {
    private const val referenceEpoch = 978307200L
    override val descriptor = PrimitiveSerialDescriptor("FoundationDate", PrimitiveKind.DOUBLE)

    override fun serialize(encoder: Encoder, value: Instant) {
        val seconds =
            BigDecimal.valueOf(value.epochSecond - referenceEpoch)
                .add(BigDecimal.valueOf(value.nano.toLong(), 9))
        if (encoder is JsonEncoder) encoder.encodeJsonElement(JsonPrimitive(seconds))
        else encoder.encodeDouble(seconds.toDouble())
    }

    override fun deserialize(decoder: Decoder): Instant {
        val seconds =
            if (decoder is JsonDecoder)
                decoder.decodeJsonElement().jsonPrimitive.content.toBigDecimal()
            else BigDecimal.valueOf(decoder.decodeDouble())
        val whole = seconds.setScale(0, RoundingMode.FLOOR).longValueExact()
        val nanos =
            seconds
                .subtract(BigDecimal.valueOf(whole))
                .movePointRight(9)
                .setScale(0, RoundingMode.HALF_UP)
                .longValueExact()
        return Instant.ofEpochSecond(whole + referenceEpoch, nanos)
    }
}
