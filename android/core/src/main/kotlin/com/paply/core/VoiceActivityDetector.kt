package com.paply.core

import kotlin.math.*

/** Mathematical port of the Swift 30 ms VAD; use one owner or a snapshot for concurrent readers. */
class VoiceActivityDetector {
    companion object {
        const val sampleRate = 16_000.0
        const val frameLength = 480
        const val frameMs = 30.0
        const val absoluteThresholdDbfs = -65.0
        const val speechAboveFloorDb = 15.0
        const val voicedAboveFloorDb = 6.0
        const val pauseAboveFloorDb = 10.0
        const val voicedPeriodicity = 0.6f
        const val brightZeroCrossings = 0.08f
        const val minRunFrames = 3
        const val voicedSpeechMs = 150.0
        const val whisperWindowFrames = 83
        const val whisperActiveFrames = 34
        const val whisperMinRuns = 3
        const val floorWindowFrames = 1000
        const val floorStepFrames = 33
        const val floorLookaheadSteps = 15
        const val minPitchLag = 40
        const val maxPitchLag = 228

        internal fun lowerBound(sorted: List<Float>, value: Float): Int {
            var low = 0
            var high = sorted.size
            while (low < high) {
                val mid = (low + high) / 2
                if (sorted[mid] < value) low = mid + 1 else high = mid
            }
            return low
        }

        fun analyze(input: FloatArray): Frame {
            val n = input.size
            if (n == 0) return Frame(-120f, 0f)
            var sum = 0f
            for (v in input) sum += v
            val mean = sum / n
            if (!mean.isFinite()) return Frame(-120f, 0f)
            val x = FloatArray(n) { input[it] - mean }
            var squares = 0f
            for (v in x) squares += v * v
            val meanSquare = squares / n
            val dbfs = max(-120.0, 10 * log10(meanSquare.toDouble()))
            if (!dbfs.isFinite() || dbfs <= -75)
                return Frame(if (dbfs.isFinite()) dbfs.toFloat() else -120f, 0f, 0f)
            var crossings = 0
            for (i in 1 until n) if ((x[i - 1] < 0) != (x[i] < 0)) crossings++
            return Frame(dbfs.toFloat(), periodicity(x), crossings.toFloat() / max(1, n - 1))
        }

        fun highPass(signal: FloatArray): FloatArray {
            val x = signal.copyOf()
            val a = 0.9428f
            repeat(2) {
                var previousOut = 0f
                var previousIn = x.firstOrNull() ?: 0f
                for (i in x.indices) {
                    val input = x[i]
                    val output = a * (previousOut + input - previousIn)
                    x[i] = output
                    previousOut = output
                    previousIn = input
                }
            }
            return x
        }

        fun periodicity(signal: FloatArray) = periodicityRaw(highPass(signal))

        fun periodicityRaw(y: FloatArray): Float {
            val n = y.size
            val maxLag = min(maxPitchLag + 1, n / 2)
            if (maxLag <= minPitchLag + 1) return 0f
            val prefix = FloatArray(n + 1)
            for (i in 0 until n) prefix[i + 1] = prefix[i] + y[i] * y[i]
            val r = FloatArray(maxLag + 1)
            for (lag in 1..maxLag) {
                val count = n - lag
                var dot = 0f
                for (i in 0 until count) dot += y[i] * y[i + lag]
                val denominator = sqrt((prefix[count] - prefix[0]) * (prefix[n] - prefix[lag]))
                r[lag] = if (denominator > 0) dot / denominator else 0f
            }
            val firstZero = (1..maxLag).firstOrNull { r[it] <= 0 } ?: return 0f
            var best = 0f
            for (lag in max(minPitchLag, firstZero + 1) until maxLag) if (
                r[lag] > r[lag - 1] && r[lag] >= r[lag + 1]
            )
                best = max(best, r[lag])
            return best
        }

        internal fun hasSyllabicBurst(runs: List<Pair<Int, Int>>): Boolean {
            var first = 0
            var active = 0
            for (last in runs.indices) {
                active += runs[last].second
                while (
                    first < last &&
                        runs[last].first + runs[last].second - runs[first].first >
                            whisperWindowFrames
                ) active -= runs[first++].second
                if (last - first + 1 >= whisperMinRuns && active >= whisperActiveFrames) return true
            }
            return false
        }
    }

    data class Frame(val dbfs: Float, val periodicity: Float, val zeroCrossings: Float = 0.5f)

    private val mutableFrames = mutableListOf<Frame>()
    val frames: List<Frame>
        get() = mutableFrames

    private val window = mutableListOf<Float>()
    private val floorHistory = mutableListOf<Float>()
    private var pending = FloatArray(0)
    private var latched = false
    var peakDbfs = -120.0
        private set

    val frameCount
        get() = frames.size

    val durationMs
        get() = frames.size * frameMs

    val lastLevelDbfs
        get() = frames.lastOrNull()?.dbfs?.toDouble() ?: -120.0

    val floorDbfs
        get() =
            if (window.isEmpty()) -120.0
            else window[max(0, ceil(window.size * 0.15).toInt() - 1)].toDouble()

    val speechDetected
        get() = latched

    internal fun snapshot(): VoiceActivityDetector =
        VoiceActivityDetector().also {
            it.mutableFrames.addAll(frames)
            it.window.addAll(window)
            it.floorHistory.addAll(floorHistory)
            it.pending = pending.copyOf()
            it.latched = latched
            it.peakDbfs = peakDbfs
        }

    fun floor(index: Int): Float =
        floorHistory.getOrNull(index / floorStepFrames + floorLookaheadSteps) ?: floorDbfs.toFloat()

    fun isActive(index: Int) =
        frames[index].dbfs >
            max(absoluteThresholdDbfs.toFloat(), floor(index) + speechAboveFloorDb.toFloat())

    fun isBrightActive(index: Int) =
        isActive(index) && frames[index].zeroCrossings >= brightZeroCrossings

    fun isVoiced(index: Int) =
        frames[index].periodicity >= voicedPeriodicity &&
            frames[index].dbfs >=
                max(
                    (absoluteThresholdDbfs - 5).toFloat(),
                    floor(index) + voicedAboveFloorDb.toFloat(),
                )

    fun isPause(index: Int) =
        frames[index].dbfs <
            max(
                (absoluteThresholdDbfs - 5).toFloat(),
                floor(index) + pauseAboveFloorDb.toFloat(),
            ) && !isVoiced(index)

    fun process(samples: FloatArray) {
        var offset = 0
        if (pending.isNotEmpty()) {
            val take = min(frameLength - pending.size, samples.size)
            pending += samples.copyOfRange(0, take)
            offset = take
            if (pending.size == frameLength) {
                insert(analyze(pending))
                pending = FloatArray(0)
            }
        }
        while (offset + frameLength <= samples.size) {
            insert(analyze(samples.copyOfRange(offset, offset + frameLength)))
            offset += frameLength
        }
        if (offset < samples.size) pending += samples.copyOfRange(offset, samples.size)
        if (!latched && frames.isNotEmpty()) latched = hasSpeech(0 until frames.size)
    }

    fun appendFrame(dbfs: Float, periodicity: Float, zeroCrossings: Float = 0.5f) {
        insert(Frame(dbfs, periodicity, zeroCrossings))
        if (!latched) latched = hasSpeech(0 until frames.size)
    }

    private fun insert(frame: Frame) {
        mutableFrames += frame
        window.add(lowerBound(window, frame.dbfs), frame.dbfs)
        if (frames.size > floorWindowFrames) {
            val leaving = frames[frames.size - floorWindowFrames - 1].dbfs
            val index = lowerBound(window, leaving)
            if (index < window.size && window[index] == leaving) window.removeAt(index)
        }
        if (frames.size % floorStepFrames == 0) floorHistory += floorDbfs.toFloat()
        peakDbfs = max(peakDbfs, frame.dbfs.toDouble())
    }

    data class Activity(
        val speechMs: Double,
        val voicedMs: Double,
        val whisperLike: Boolean,
        val peakDbfs: Double,
        val activeRuns: Int = 0,
    )

    fun activity(range: IntRange): Activity {
        var speechFrames = 0
        var voicedFrames = 0
        var activeStart = 0
        var activeLength = 0
        var voicedLength = 0
        val runs = mutableListOf<Pair<Int, Int>>()
        var peak = -120f
        for (index in max(0, range.first) until min(frames.size, range.last + 1)) {
            peak = max(peak, frames[index].dbfs)
            if (isActive(index)) speechFrames++
            if (isBrightActive(index)) {
                if (activeLength == 0) activeStart = index
                activeLength++
            } else {
                if (activeLength >= minRunFrames) runs += activeStart to activeLength
                activeLength = 0
            }
            if (isVoiced(index)) voicedLength++
            else {
                if (voicedLength >= minRunFrames) voicedFrames += voicedLength
                voicedLength = 0
            }
        }
        if (activeLength >= minRunFrames) runs += activeStart to activeLength
        if (voicedLength >= minRunFrames) voicedFrames += voicedLength
        return Activity(
            speechFrames * frameMs,
            voicedFrames * frameMs,
            hasSyllabicBurst(runs),
            peak.toDouble(),
            runs.size,
        )
    }

    fun voicedMs(start: Double, end: Double): Double {
        val first = max(0, floor(start * 1000 / frameMs).toInt())
        val last = min(frames.size, ceil(end * 1000 / frameMs).toInt())
        return if (last > first) activity(first until last).voicedMs else 0.0
    }

    fun hasSpeech(range: IntRange) =
        activity(range).let { it.voicedMs >= voicedSpeechMs || it.whisperLike }

    fun hasAnyActivity(range: IntRange) =
        activity(range).let { it.voicedMs >= minRunFrames * frameMs || it.activeRuns > 0 }

    fun trailingPauseFrames(endingAt: Int): Int {
        var count = 0
        var index = min(endingAt, frames.size) - 1
        while (index >= 0 && isPause(index)) {
            count++
            index--
        }
        return count
    }

    fun meta(frameRange: IntRange = 0 until frames.size): VoiceActivityMeta {
        val range = max(0, frameRange.first) until min(frames.size, frameRange.last + 1)
        val a = activity(range)
        val duration = max(0, range.last + 1 - range.first) * frameMs
        val peak = if (range.isEmpty()) -120.0 else a.peakDbfs
        return VoiceActivityMeta(
            duration,
            duration,
            a.speechMs,
            peak,
            min(floorDbfs, peak),
            frameMs,
            a.voicedMs,
        )
    }
}
