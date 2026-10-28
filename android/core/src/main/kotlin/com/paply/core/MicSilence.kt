package com.paply.core

import kotlin.math.*

data class MicBufferLevel(
    var samples: Int = 0,
    var peak: Float = 0f,
    var sumSquares: Double = 0.0,
    var acSumSquares: Double = 0.0,
    var diffSumSquares: Double = 0.0,
    var allZero: Boolean = true,
    var nonFinite: Int = 0,
) {
    companion object {
        fun measure(x: FloatArray): MicBufferLevel {
            val level = MicBufferLevel()
            if (x.isEmpty()) return level
            level.samples = x.size
            var sum = 0.0
            var finite = 0
            for (value in x) {
                if (!value.isFinite()) {
                    level.nonFinite++
                    continue
                }
                finite++
                val v = value.toDouble()
                sum += v
                level.sumSquares += v * v
                level.peak = max(level.peak, abs(value))
                if (value != 0f) level.allZero = false
            }
            if (level.nonFinite > 0) level.allZero = false
            val mean = if (finite > 0) sum / finite else 0.0
            var previous: Float? = null
            for (value in x) if (value.isFinite()) {
                val ac = value.toDouble() - mean
                level.acSumSquares += ac * ac
                previous?.let {
                    val d = value.toDouble() - it.toDouble()
                    level.diffSumSquares += d * d
                }
                previous = value
            }
            return level
        }
    }

    fun merge(other: MicBufferLevel) {
        samples += other.samples
        peak = max(peak, other.peak)
        sumSquares += other.sumSquares
        acSumSquares += other.acSumSquares
        diffSumSquares += other.diffSumSquares
        allZero = allZero && other.allZero
        nonFinite += other.nonFinite
    }

    val acRmsDbfs
        get() = MicLevel.dbfs(if (samples > 0) acSumSquares / samples else 0.0)

    val isOffsetDominated: Boolean
        get() {
            if (samples <= 0) return false
            val ac = acSumSquares / samples
            val dc = max(0.0, sumSquares - acSumSquares) / samples
            return dc > 1e-6 && dc > 10 * ac
        }

    val isDigitalSilence
        get() =
            samples > 0 &&
                (allZero || nonFinite > 0 || acRmsDbfs < MicSilenceDetector.thresholdDbfs)
}

object MicLevel {
    const val floorDbfs = -160.0

    fun dbfs(meanSquare: Double) =
        if (meanSquare.isFinite() && meanSquare > 0) max(floorDbfs, 10 * log10(meanSquare))
        else floorDbfs

    fun dbfs(peak: Float) =
        if (peak.isFinite() && peak > 0) max(floorDbfs, 20 * log10(peak.toDouble())) else floorDbfs
}

class MicSilenceDetector {
    companion object {
        const val thresholdDbfs = -120.0
        const val silentAfterSeconds = 1.5
    }

    enum class Change {
        becameSilent,
        becameAlive,
    }

    var isSilent = false
        private set

    var silentSeconds = 0.0
        private set

    var heardSignal = false
        private set

    fun feed(level: MicBufferLevel, seconds: Double): Change? {
        if (level.samples <= 0 || !(seconds > 0)) return null
        if (level.isDigitalSilence) {
            silentSeconds += seconds
            if (!isSilent && silentSeconds >= silentAfterSeconds - 1e-6) {
                isSilent = true
                return Change.becameSilent
            }
            return null
        }
        silentSeconds = 0.0
        heardSignal = true
        if (isSilent) {
            isSilent = false
            return Change.becameAlive
        }
        return null
    }

    fun reset() {
        isSilent = false
        silentSeconds = 0.0
        heardSignal = false
    }
}

class MicInputStats {
    var buffers = 0
        private set

    var zeroBuffers = 0
        private set

    var silentBuffers = 0
        private set

    var offsetBuffers = 0
        private set

    var samples = 0
        private set

    var peak = 0f
        private set

    var sumSquares = 0.0
        private set

    var acSumSquares = 0.0
        private set

    var diffSumSquares = 0.0
        private set

    var convertedPeak = 0f
    var restarts = 0

    fun add(level: MicBufferLevel) {
        if (level.samples <= 0) return
        buffers++
        if (level.allZero) zeroBuffers++
        if (level.isDigitalSilence) silentBuffers++
        if (level.isOffsetDominated) offsetBuffers++
        samples += level.samples
        peak = max(peak, level.peak)
        sumSquares += level.sumSquares
        acSumSquares += level.acSumSquares
        diffSumSquares += level.diffSumSquares
    }

    val peakDbfs
        get() = MicLevel.dbfs(peak)

    val rmsDbfs
        get() = MicLevel.dbfs(if (samples > 0) sumSquares / samples else 0.0)

    val acRmsDbfs
        get() = MicLevel.dbfs(if (samples > 0) acSumSquares / samples else 0.0)

    val diffRmsDbfs
        get() = MicLevel.dbfs(if (samples > 0) diffSumSquares / samples else 0.0)

    val convertedPeakDbfs
        get() = MicLevel.dbfs(convertedPeak)

    val wasSilent
        get() = buffers >= 3 && silentBuffers == buffers
}

class NoSpeechStreak {
    companion object {
        const val minSeconds = 2.0
        const val windowSeconds = 180.0
        const val needed = 2
    }

    var times: List<Double> = emptyList()
        private set

    fun speechHeard() {
        times = emptyList()
    }

    fun completed(speech: Boolean, seconds: Double, now: Double): Boolean {
        if (speech) {
            times = emptyList()
            return false
        }
        if (!(seconds >= minSeconds - 1e-9)) return false
        times = times.filter { now - it <= windowSeconds } + now
        if (times.size < needed) return false
        times = emptyList()
        return true
    }

    fun keepArmed(now: Double) {
        times = List(needed - 1) { now }
    }
}
