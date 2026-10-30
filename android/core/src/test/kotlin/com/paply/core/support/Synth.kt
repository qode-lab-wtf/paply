package com.paply.core

import kotlin.math.*

/** Same xorshift64 fixtures and Float32 arithmetic as Swift Support/Synth.swift. */
internal object Synth {
    const val rate = 16000.0

    fun samples(seconds: Double) = (seconds * rate).toInt()

    fun amplitude(dbfs: Double) = 10.0.pow(dbfs / 20).toFloat()

    fun noise(seconds: Double, dbfs: Double, seed: Long = 42): FloatArray {
        var state = (seed.toULong() * 0x9E3779B97F4A7C15uL) or 1uL
        val scale = amplitude(dbfs) * 1.732f
        return FloatArray(samples(seconds)) {
            state = state xor (state shl 13)
            state = state xor (state shr 7)
            state = state xor (state shl 17)
            ((state % 2_000_001uL).toDouble().div(1_000_000).toFloat() - 1) * scale
        }
    }

    fun voice(seconds: Double, dbfs: Double, f0: Double = 140.0): FloatArray {
        val out =
            FloatArray(samples(seconds)) { i ->
                (1..8).sumOf { k -> sin(2 * PI * f0 * k * (i / rate)) / k }.toFloat()
            }
        val rms = sqrt(out.sumOf { (it * it).toDouble() } / max(1, out.size))
        val gain = (amplitude(dbfs).toDouble() / max(rms, 1e-9)).toFloat()
        return FloatArray(out.size) { out[it] * gain }
    }

    fun speech(
        seconds: Double,
        dbfs: Double = -24.0,
        syllable: Double = 0.22,
        gap: Double = 0.09,
    ): FloatArray {
        val out = FloatArray(samples(seconds))
        var offset = 0
        var f0 = 120.0
        while (offset < out.size) {
            val v = voice(syllable, dbfs, f0)
            val count = min(v.size, out.size - offset)
            v.copyInto(out, offset, 0, count)
            offset += count + samples(gap)
            f0 = if (f0 >= 180) 120.0 else f0 + 15
        }
        return out
    }

    fun silence(seconds: Double) = FloatArray(samples(seconds))

    fun withFloor(signal: FloatArray, dbfs: Double = -60.0, seed: Long = 7): FloatArray {
        val floor = noise(signal.size / rate, dbfs, seed)
        return FloatArray(min(signal.size, floor.size)) { signal[it] + floor[it] }
    }

    fun clicks(seconds: Double, every: Double = 0.3, dbfs: Double = -10.0): FloatArray {
        val out = silence(seconds)
        val length = samples(0.005)
        var position = samples(0.1)
        val a = amplitude(dbfs)
        while (position + length < out.size) {
            for (i in 0 until length) out[position + i] = if (i % 2 == 0) a else -a
            position += samples(every)
        }
        return out
    }

    fun brown(seconds: Double, dbfs: Double, seed: Long = 5): FloatArray {
        val white = noise(seconds, 0.0, seed)
        var accumulator = 0f
        return scaled(
            FloatArray(white.size) {
                accumulator = 0.995f * accumulator + white[it]
                accumulator
            },
            dbfs,
        )
    }

    fun tones(seconds: Double, partials: List<Pair<Double, Double>>, dbfs: Double) =
        scaled(
            FloatArray(samples(seconds)) { i ->
                partials
                    .sumOf { (frequency, amplitude) ->
                        amplitude * sin(2 * PI * frequency * (i / rate))
                    }
                    .toFloat()
            },
            dbfs,
        )

    fun ramp(signal: FloatArray, from: Double, to: Double): FloatArray {
        val n = max(1, signal.size - 1)
        return FloatArray(signal.size) {
            signal[it] * 10.0.pow((from + (to - from) * it / n) / 20).toFloat()
        }
    }

    fun scaled(signal: FloatArray, dbfs: Double): FloatArray {
        val rms = sqrt(signal.sumOf { (it * it).toDouble() } / max(1, signal.size))
        val gain = (amplitude(dbfs).toDouble() / max(rms, 1e-12)).toFloat()
        return FloatArray(signal.size) { signal[it] * gain }
    }
}

internal fun detector(samples: FloatArray, block: Int = 1600) =
    VoiceActivityDetector().also { vad ->
        for (offset in samples.indices step block) vad.process(
            samples.copyOfRange(offset, minOf(offset + block, samples.size)),
        )
    }

internal fun feed(pipeline: DictationPipeline, samples: FloatArray) {
    for (offset in samples.indices step 1600) pipeline.append(
        samples.copyOfRange(offset, minOf(offset + 1600, samples.size)),
    )
}
