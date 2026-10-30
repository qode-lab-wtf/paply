package com.paply.core

import kotlin.math.*
import kotlinx.coroutines.runBlocking
import org.junit.Test

class MicSilenceTests {
    private fun level(samples: FloatArray) = MicBufferLevel.measure(samples)

    private fun buffers(samples: FloatArray) =
        samples.indices.step(1600).map { samples.copyOfRange(it, minOf(it + 1600, samples.size)) }

    private fun run(
        d: MicSilenceDetector,
        samples: FloatArray,
    ): List<Pair<Double, MicSilenceDetector.Change>> {
        var t = 0.0
        val changes = mutableListOf<Pair<Double, MicSilenceDetector.Change>>()
        for (buffer in buffers(samples)) {
            val seconds = buffer.size / Synth.rate
            t += seconds
            d.feed(level(buffer), seconds)?.let { changes += t to it }
        }
        return changes
    }

    @Test
    fun exactZerosAreDigitalSilence() {
        val v = level(FloatArray(4800))
        expect(v.allZero && v.isDigitalSilence && v.peak == 0f && v.acRmsDbfs == MicLevel.floorDbfs)
    }

    @Test
    fun standingOffsetIsSilenceButNotZero() {
        val v = level(FloatArray(4800) { 0.16f })
        expect(!v.allZero && v.isDigitalSilence)
        expect(abs(MicLevel.dbfs(v.peak) + 15.9) < 0.1)
    }

    @Test
    fun offsetDominatedBuffersAreCountedForTheLog() {
        val offset = level(FloatArray(4800) { (0.16 + 0.02 * it / 4800).toFloat() })
        expect(offset.isOffsetDominated && !offset.isDigitalSilence)
        expect(!level(Synth.noise(0.1, -20.0)).isOffsetDominated)
        expect(!level(Synth.voice(0.1, -20.0)).isOffsetDominated)
        expect(!level(FloatArray(480)).isOffsetDominated)
        val stats = MicInputStats()
        stats.add(offset)
        stats.add(level(Synth.noise(0.1, -40.0)))
        expect(stats.offsetBuffers == 1 && stats.silentBuffers == 0)
    }

    @Test
    fun thresholdSitsAtMinus120Dbfs() {
        expect(level(Synth.noise(0.1, -130.0)).isDigitalSilence)
        expect(!level(Synth.noise(0.1, -110.0)).isDigitalSilence)
        expect(!level(Synth.noise(0.1, -90.0)).isDigitalSilence)
        expect(!level(Synth.voice(0.1, -60.0)).isDigitalSilence)
    }

    @Test
    fun unusableValuesCountAsSilence() {
        val a = Synth.noise(0.1, -40.0)
        a[10] = Float.NaN
        val v = level(a)
        expect(v.nonFinite == 1 && v.isDigitalSilence)
    }

    @Test
    fun emptyBufferIsNeverSilence() {
        val v = level(floatArrayOf())
        val d = MicSilenceDetector()
        expect(!v.isDigitalSilence)
        expect(d.feed(v, 0.1) == null)
        expect(!d.heardSignal)
    }

    @Test
    fun oneLiveChannelKeepsTheBufferAlive() {
        val v = level(FloatArray(4800))
        v.merge(level(Synth.noise(0.3, -80.0)))
        expect(!v.allZero && !v.isDigitalSilence)
    }

    @Test
    fun silentAfterOneAndAHalfSeconds() {
        val d = MicSilenceDetector()
        val c = run(d, Synth.silence(3.0))
        expect(c.size == 1 && c[0].second == MicSilenceDetector.Change.becameSilent)
        expect(abs(c[0].first - 1.5) < 0.001)
        expect(d.isSilent && !d.heardSignal)
    }

    @Test
    fun shortSilenceIsNotDead() {
        val d = MicSilenceDetector()
        expect(run(d, Synth.silence(1.4)).isEmpty())
        expect(!d.isSilent)
    }

    @Test
    fun anyRealBufferResetsTheCount() {
        val d = MicSilenceDetector()
        expect(run(d, Synth.silence(1.0) + Synth.noise(0.1, -95.0) + Synth.silence(1.0)).isEmpty())
        expect(d.heardSignal)
        expect(abs(d.silentSeconds - 1) < 0.001)
    }

    @Test
    fun realMicrophoneNeverTriggers() {
        val d = MicSilenceDetector()
        expect(
            run(
                    d,
                    Synth.speech(3.0) +
                        Synth.noise(5.0, -95.0) +
                        Synth.withFloor(Synth.speech(2.0), -85.0),
                )
                .isEmpty(),
        )
        expect(d.heardSignal)
    }

    @Test
    fun reportsWhenTheSignalComesBack() {
        val d = MicSilenceDetector()
        val c = run(d, Synth.silence(2.0) + Synth.noise(0.2, -70.0) + Synth.silence(1.0))
        expect(
            c.map { it.second } ==
                listOf(
                    MicSilenceDetector.Change.becameSilent,
                    MicSilenceDetector.Change.becameAlive,
                ),
        )
        expect(!d.isSilent)
    }

    @Test
    fun resetForgetsEverything() {
        val d = MicSilenceDetector()
        run(d, Synth.noise(0.1, -60.0) + Synth.silence(2.0))
        expect(d.isSilent && d.heardSignal)
        d.reset()
        expect(!d.isSilent && !d.heardSignal && d.silentSeconds == 0.0)
        expect(
            run(d, Synth.silence(1.6)).map { it.second } ==
                listOf(MicSilenceDetector.Change.becameSilent),
        )
    }

    @Test
    fun recordingStatsForTheLog() {
        val s = MicInputStats()
        for (b in buffers(Synth.silence(0.3))) s.add(level(b))
        s.add(level(FloatArray(1600) { 0.01f }))
        expect(s.buffers == 4 && s.zeroBuffers == 3 && s.silentBuffers == 4 && s.wasSilent)
        expect(abs(s.peakDbfs + 40) < 0.01)
        expect(s.acRmsDbfs == MicLevel.floorDbfs)
        for (b in buffers(Synth.noise(0.2, -30.0))) s.add(level(b))
        expect(s.buffers == 6 && s.silentBuffers == 4 && !s.wasSilent)
        expect(s.acRmsDbfs > -40 && s.acRmsDbfs < -30)
        expect(s.diffRmsDbfs > MicLevel.floorDbfs)
    }

    @Test
    fun tooShortToJudge() {
        val s = MicInputStats()
        for (b in buffers(Synth.silence(0.2))) s.add(level(b))
        expect(s.silentBuffers == 2 && !s.wasSilent)
        expect(
            MicInputStats().peakDbfs == MicLevel.floorDbfs &&
                MicInputStats().rmsDbfs == MicLevel.floorDbfs,
        )
    }

    @Test
    fun pipelineDropsTheSilentStartAfterARestart() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hallo.") }
            .use { s ->
                val p = s.pipeline(options = PipelineOptions(polish = false))
                p.append(Synth.silence(2.0))
                expect(p.discardSilentStart())
                p.append(Synth.withFloor(Synth.speech(2.0)))
                expect(p.speechDetected && !p.discardSilentStart())
                val out = p.finish()
                expect(out.text == "Hallo.")
                expect(abs(out.timings.audioSeconds - 2) < 0.001)
                expect(!p.discardSilentStart())
            }
    }

    private fun run(s: NoSpeechStreak, vararg recordings: Triple<Boolean, Double, Double>) =
        recordings.map {
            s.completed(it.first, it.second, it.third)
        }

    private fun r(speech: Boolean, seconds: Double, at: Double) = Triple(speech, seconds, at)

    @Test
    fun twoLongEmptyRecordingsTrigger() {
        val s = NoSpeechStreak()
        expect(run(s, r(false, 19.4, 0.0), r(false, 2.2, 28.0)) == listOf(false, true))
        expect(s.times.isEmpty())
    }

    @Test
    fun exactlyTwoSecondsCounts() {
        expect(run(NoSpeechStreak(), r(false, 2.0, 0.0), r(false, 2.0, 1.0)) == listOf(false, true))
    }

    @Test
    fun shortRecordingsNeitherCountNorBreakTheStreak() {
        val s = NoSpeechStreak()
        expect(run(s, r(false, 1.9, 0.0), r(false, 1.9, 5.0)) == listOf(false, false))
        expect(s.times.isEmpty())
        expect(
            run(s, r(false, 3.0, 10.0), r(false, 0.8, 12.0), r(false, 3.0, 20.0)) ==
                listOf(false, false, true),
        )
    }

    @Test
    fun speechResetsTheCount() {
        val s = NoSpeechStreak()
        expect(
            run(s, r(false, 4.0, 0.0), r(true, 4.0, 10.0), r(false, 4.0, 20.0)) ==
                listOf(false, false, false),
        )
        s.speechHeard()
        expect(run(s, r(false, 4.0, 30.0), r(false, 4.0, 40.0)) == listOf(false, true))
    }

    @Test
    fun moreThanThreeMinutesApartDoesNotTrigger() {
        val s = NoSpeechStreak()
        expect(
            run(s, r(false, 5.0, 0.0), r(false, 5.0, 181.0), r(false, 5.0, 361.0)) ==
                listOf(false, false, true),
        )
        expect(run(s, r(false, 5.0, 1000.0), r(false, 5.0, 1180.0)) == listOf(false, true))
    }

    @Test
    fun triggersAgainOnlyAfterTwoMore() {
        expect(
            run(
                NoSpeechStreak(),
                r(false, 3.0, 0.0),
                r(false, 3.0, 10.0),
                r(false, 3.0, 20.0),
                r(false, 3.0, 30.0),
            ) == listOf(false, true, false, true),
        )
    }

    @Test
    fun incidentSequenceTriggersAtTheSecondDictation() {
        expect(
            run(
                NoSpeechStreak(),
                r(false, 19.4, 0.0),
                r(false, 2.2, 28.3),
                r(false, 2.0, 31.5),
                r(false, 2.2, 43.0),
            ) == listOf(false, true, false, true),
        )
    }

    @Test
    fun keepArmedTriggersOnTheNextSilentRecording() {
        val s = NoSpeechStreak()
        expect(!s.completed(false, 3.0, 0.0))
        expect(s.completed(false, 3.0, 10.0))
        s.keepArmed(10.0)
        expect(s.completed(false, 3.0, 20.0))
        s.keepArmed(30.0)
        expect(!s.completed(true, 3.0, 40.0))
        expect(!s.completed(false, 3.0, 50.0))
    }
}
