package com.paply.core

class ChunkPlanner {
    var minChunkSeconds = 10.0
    var pauseSeconds = 0.6
    var relaxedAfterSeconds = 20.0
    var relaxedPauseSeconds = 0.4
    var chunkStartFrame = 0
        private set

    // All durations are positive: Swift rounded() is nearest, ties away from zero.
    private fun frames(seconds: Double) =
        kotlin.math.floor(seconds * 1000 / VoiceActivityDetector.frameMs + 0.5).toInt()

    fun nextCut(vad: VoiceActivityDetector): IntRange? {
        val end = vad.frameCount
        val pause = vad.trailingPauseFrames(end)
        if (pause <= 0) return null
        val pauseStart = end - pause
        val spoken = pauseStart - chunkStartFrame
        if (spoken <= 0) return null
        val required =
            frames(
                if (spoken * VoiceActivityDetector.frameMs >= relaxedAfterSeconds * 1000)
                    relaxedPauseSeconds
                else pauseSeconds,
            )
        if (pause < required) return null
        val cut = pauseStart + required / 2
        if (
            cut - chunkStartFrame < frames(minChunkSeconds) ||
                !vad.hasSpeech(chunkStartFrame until pauseStart)
        )
            return null
        val chunk = chunkStartFrame until cut
        chunkStartFrame = cut
        return chunk
    }
}
