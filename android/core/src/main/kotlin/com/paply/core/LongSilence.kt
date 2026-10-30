package com.paply.core

/** Live and file transcription: omit confidently silent >= 2 s runs, keeping 240 ms word edges.
 * Uncertain, bright (whisper-like) or periodic (even quiet voiced) frames are always kept.
 * This does not stop capture and does not filter text or trust Whisper's no_speech_prob.
 */
object LongSilence {
    // At 16-bit capture, -85 dBFS is under two RMS quantization steps. The emulator's
    // idle dither (-2/+1) can be almost perfectly periodic, but carries no speech.
    // Quiet speech above this floor is still protected by pitch/brightness/context.
    const val quantizationFloorDbfs = -85f
    fun ranges(vad: VoiceActivityDetector, start: Int, end: Int): List<IntRange> {
        val n = VoiceActivityDetector.frameLength
        val ranges = mutableListOf<IntRange>()
        var keepStart = start
        var silenceStart = -1
        fun closeSilence(frameEnd: Int) {
            if (silenceStart < 0) return
            if ((frameEnd - silenceStart) * VoiceActivityDetector.frameMs >= 2000) {
                val cut = maxOf(keepStart, silenceStart * n + 8 * n).coerceAtMost(end)
                // No all-silence leading/trailing uploads; padding belongs to adjacent speech.
                if (silenceStart * n > keepStart && cut > keepStart) ranges += keepStart until cut
                keepStart = maxOf(keepStart, frameEnd * n - 8 * n).coerceAtMost(end)
                if (frameEnd * n >= end - n) keepStart = end
            }
            silenceStart = -1
        }
        for (i in (start + n - 1) / n until minOf(end / n, vad.frameCount)) {
            val f = vad.frames[i]
            // File mode measures pitch down to -100 dBFS, so quiet voiced speech is
            // protected too. With ordinary live VAD, missing features remain unknown.
            val measured = f.dbfs > -75 || vad.measuresQuietFeatures
            val quiet = f.dbfs <= quantizationFloorDbfs || (measured && vad.isPause(i) &&
                f.periodicity < .3f && f.dbfs < -50 && f.dbfs <= maxOf(quantizationFloorDbfs, vad.floor(i) + 3) &&
                (f.dbfs <= -75 || f.zeroCrossings < VoiceActivityDetector.brightZeroCrossings))
            if (quiet) { if (silenceStart < 0) silenceStart = i }
            else closeSilence(i)
        }
        closeSilence(minOf(end / n, vad.frameCount))
        if (keepStart < end) ranges += keepStart until end
        return ranges
    }
}
