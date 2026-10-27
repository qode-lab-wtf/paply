import Foundation
import Testing
@testable import PaplyKit

private func level(_ samples: [Float]) -> MicBufferLevel {
    samples.withUnsafeBufferPointer { MicBufferLevel.measure($0) }
}

/// 100-ms-Puffer wie im Audio-Tap (hier 16 kHz statt 48 kHz – die Regel hängt nur an der Zeit).
private func buffers(_ samples: [Float], seconds: Double = 0.1) -> [[Float]] {
    let size = Int(seconds * Synth.rate)
    return stride(from: 0, to: samples.count, by: size).map { Array(samples[$0..<min($0 + size, samples.count)]) }
}

/// Speist Puffer ein und liefert alle Wechsel mit dem Zeitpunkt (Sekunden ab Beginn).
private func run(_ detector: inout MicSilenceDetector, _ samples: [Float]) -> [(Double, MicSilenceDetector.Change)] {
    var changes: [(Double, MicSilenceDetector.Change)] = []
    var t = 0.0
    for buffer in buffers(samples) {
        let seconds = Double(buffer.count) / Synth.rate
        t += seconds
        if let change = detector.feed(level(buffer), seconds: seconds) { changes.append((t, change)) }
    }
    return changes
}

@Suite("Totes Mikro: digitale Stille erkennen") struct MicSilenceTests {
    @Test func exactZerosAreDigitalSilence() {
        let zeros = level([Float](repeating: 0, count: 4_800))
        #expect(zeros.allZero)
        #expect(zeros.isDigitalSilence)
        #expect(zeros.peak == 0)
        #expect(zeros.acRmsDbfs == MicLevel.floorDbfs)
    }

    @Test func standingOffsetIsSilenceButNotZero() {
        // Ein stehender Gleichanteil (z. B. stromloser Wandler) ist laut, enthält aber keinen Ton
        let dc = level([Float](repeating: 0.16, count: 4_800))
        #expect(!dc.allZero)
        #expect(dc.isDigitalSilence)
        #expect(abs(MicLevel.dbfs(peak: dc.peak) - -15.9) < 0.1)
    }

    @Test func offsetDominatedBuffersAreCountedForTheLog() {
        // wandernder Gleichanteil um −16 dBFS mit wenig Wechselanteil: nicht still, aber verdächtig
        let drift = (0..<4_800).map { Float(0.16 + 0.02 * Double($0) / 4_800) }
        let offset = level(drift)
        #expect(offset.isOffsetDominated)
        #expect(!offset.isDigitalSilence)
        // echter Ton (ohne Gleichanteil) und Nullen sind es nicht
        #expect(!level(Synth.noise(0.1, dbfs: -20)).isOffsetDominated)
        #expect(!level(Synth.voice(0.1, dbfs: -20)).isOffsetDominated)
        #expect(!level([Float](repeating: 0, count: 480)).isOffsetDominated)
        var stats = MicInputStats()
        stats.add(offset)
        stats.add(level(Synth.noise(0.1, dbfs: -40)))
        #expect(stats.offsetBuffers == 1)
        #expect(stats.silentBuffers == 0)
    }

    @Test func thresholdSitsAtMinus120Dbfs() {
        #expect(level(Synth.noise(0.1, dbfs: -130)).isDigitalSilence)
        #expect(!level(Synth.noise(0.1, dbfs: -110)).isDigitalSilence)
        // leises Raumrauschen und Sprache sind nie „still“
        #expect(!level(Synth.noise(0.1, dbfs: -90)).isDigitalSilence)
        #expect(!level(Synth.voice(0.1, dbfs: -60)).isDigitalSilence)
    }

    @Test func unusableValuesCountAsSilence() {
        var samples = Synth.noise(0.1, dbfs: -40)
        samples[10] = .nan
        let broken = level(samples)
        #expect(broken.nonFinite == 1)
        #expect(broken.isDigitalSilence)
    }

    @Test func emptyBufferIsNeverSilence() {
        let empty = level([])
        #expect(!empty.isDigitalSilence)
        var detector = MicSilenceDetector()
        #expect(detector.feed(empty, seconds: 0.1) == nil)
        #expect(!detector.heardSignal)
    }

    @Test func oneLiveChannelKeepsTheBufferAlive() {
        var merged = level([Float](repeating: 0, count: 4_800))
        merged.merge(level(Synth.noise(0.3, dbfs: -80)))
        #expect(!merged.allZero)
        #expect(!merged.isDigitalSilence)
    }

    @Test func silentAfterOneAndAHalfSeconds() {
        var detector = MicSilenceDetector()
        let changes = run(&detector, Synth.silence(3))
        #expect(changes.count == 1)
        #expect(changes.first?.1 == .becameSilent)
        #expect(abs((changes.first?.0 ?? 0) - 1.5) < 0.001)
        #expect(detector.isSilent)
        #expect(!detector.heardSignal)
    }

    @Test func shortSilenceIsNotDead() {
        var detector = MicSilenceDetector()
        let changes = run(&detector, Synth.silence(1.4))
        #expect(changes.isEmpty)
        #expect(!detector.isSilent)
    }

    @Test func anyRealBufferResetsTheCount() {
        var detector = MicSilenceDetector()
        let samples = Synth.silence(1.0) + Synth.noise(0.1, dbfs: -95) + Synth.silence(1.0)
        #expect(run(&detector, samples).isEmpty)
        #expect(detector.heardSignal)
        #expect(abs(detector.silentSeconds - 1.0) < 0.001)
    }

    @Test func realMicrophoneNeverTriggers() {
        var detector = MicSilenceDetector()
        // Sprache mit echten Nullen in den Wortlücken (synthetisch), leiser Raum, Pausen im Raumrauschen
        let samples = Synth.speech(3) + Synth.noise(5, dbfs: -95) + Synth.withFloor(Synth.speech(2), dbfs: -85)
        #expect(run(&detector, samples).isEmpty)
        #expect(detector.heardSignal)
    }

    @Test func reportsWhenTheSignalComesBack() {
        var detector = MicSilenceDetector()
        let changes = run(&detector, Synth.silence(2) + Synth.noise(0.2, dbfs: -70) + Synth.silence(1))
        #expect(changes.map(\.1) == [.becameSilent, .becameAlive])
        #expect(!detector.isSilent)
    }

    @Test func resetForgetsEverything() {
        var detector = MicSilenceDetector()
        _ = run(&detector, Synth.noise(0.1, dbfs: -60) + Synth.silence(2))
        #expect(detector.isSilent && detector.heardSignal)
        detector.reset()
        #expect(detector == MicSilenceDetector())
        // nach dem Neustart zählt die Stille wieder von vorn und meldet erneut
        #expect(run(&detector, Synth.silence(1.6)).map(\.1) == [.becameSilent])
    }

    @Test func recordingStatsForTheLog() {
        var stats = MicInputStats()
        for buffer in buffers(Synth.silence(0.3)) { stats.add(level(buffer)) }
        for buffer in buffers([Float](repeating: 0.01, count: 1_600)) { stats.add(level(buffer)) }
        #expect(stats.buffers == 4)
        #expect(stats.zeroBuffers == 3)
        #expect(stats.silentBuffers == 4)
        #expect(stats.wasSilent)
        #expect(abs(stats.peakDbfs - -40) < 0.01)
        #expect(stats.acRmsDbfs == MicLevel.floorDbfs)

        for buffer in buffers(Synth.noise(0.2, dbfs: -30)) { stats.add(level(buffer)) }
        #expect(stats.buffers == 6)
        #expect(stats.silentBuffers == 4)
        #expect(!stats.wasSilent)
        #expect(stats.acRmsDbfs > -40 && stats.acRmsDbfs < -30)
        #expect(stats.diffRmsDbfs > MicLevel.floorDbfs)
    }

    @Test func tooShortToJudge() {
        var stats = MicInputStats()
        for buffer in buffers(Synth.silence(0.2)) { stats.add(level(buffer)) }
        #expect(stats.silentBuffers == 2)
        #expect(!stats.wasSilent) // ein, zwei Anlaufpuffer sagen nichts
        #expect(MicInputStats().peakDbfs == MicLevel.floorDbfs)
        #expect(MicInputStats().rmsDbfs == MicLevel.floorDbfs)
    }

    @Test func pipelineDropsTheSilentStartAfterARestart() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.transcription("Hallo.")
        }
        var options = PipelineOptions()
        options.polish = false
        let p = DictationPipeline(settings: PaplySettings(), recentRawDictations: [], options: options,
                                  client: server.client(), catalog: ModelCatalog())
        await p.append(Synth.silence(2)) // stummes Mikro
        #expect(await p.discardSilentStart())
        await p.append(Synth.withFloor(Synth.speech(2)))
        #expect(await p.speechDetected)
        #expect(await p.discardSilentStart() == false) // nach erkannter Sprache wird nichts mehr verworfen
        let outcome = await p.finish()
        #expect(outcome.text == "Hallo.")
        #expect(abs(outcome.timings.audioSeconds - 2) < 0.001)
        #expect(await p.discardSilentStart() == false)
    }
}

/// Abgeschlossene Aufnahmen nacheinander melden: (Sprache?, Tonlänge s, Zeitpunkt s) → ausgelöst?
private func run(_ streak: inout NoSpeechStreak, _ recordings: [(speech: Bool, seconds: Double, at: Double)]) -> [Bool] {
    recordings.map { streak.completed(speech: $0.speech, seconds: $0.seconds, now: $0.at) }
}

@Suite("Zweimal nichts verstanden: Mikro neu starten") struct NoSpeechStreakTests {
    @Test func twoLongEmptyRecordingsTrigger() {
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 19.4, 0), (false, 2.2, 28)]) == [false, true])
        #expect(streak.times.isEmpty) // danach von vorn
    }

    @Test func exactlyTwoSecondsCounts() {
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 2.0, 0), (false, 2.0, 1)]) == [false, true])
    }

    @Test func shortRecordingsNeitherCountNorBreakTheStreak() {
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 1.9, 0), (false, 1.9, 5)]) == [false, false])
        #expect(streak.times.isEmpty)
        #expect(run(&streak, [(false, 3, 10), (false, 0.8, 12), (false, 3, 20)]) == [false, false, true])
    }

    @Test func speechResetsTheCount() {
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 4, 0), (true, 4, 10), (false, 4, 20)]) == [false, false, false])
        streak.speechHeard() // z. B. Sprache in einem abgebrochenen Diktat
        #expect(run(&streak, [(false, 4, 30), (false, 4, 40)]) == [false, true])
    }

    @Test func moreThanThreeMinutesApartDoesNotTrigger() {
        var streak = NoSpeechStreak()
        // die zweite zählt als neuer Anfang; genau 3 Minuten Abstand lösen noch aus
        #expect(run(&streak, [(false, 5, 0), (false, 5, 181), (false, 5, 361)]) == [false, false, true])
        #expect(run(&streak, [(false, 5, 1_000), (false, 5, 1_180)]) == [false, true])
    }

    @Test func triggersAgainOnlyAfterTwoMore() {
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 3, 0), (false, 3, 10), (false, 3, 20), (false, 3, 30)]) == [false, true, false, true])
    }

    @Test func incidentSequenceTriggersAtTheSecondDictation() {
        // Vorfall 27.10., 22:13–22:14: Tonlängen der Diktate (mit 0,5 s Vorlauf), alle ohne Sprache
        var streak = NoSpeechStreak()
        #expect(run(&streak, [(false, 19.4, 0), (false, 2.2, 28.3), (false, 2.0, 31.5), (false, 2.2, 43)])
                == [false, true, false, true])
    }
}
