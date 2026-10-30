import AVFoundation
import Foundation
import Testing
@testable import PaplyKit

private func detector(_ samples: [Float], block: Int = 1_600) -> VoiceActivityDetector {
    var vad = VoiceActivityDetector()
    var offset = 0
    while offset < samples.count {
        vad.process(Array(samples[offset..<min(offset + block, samples.count)]))
        offset += block
    }
    return vad
}

@Suite struct VoiceActivityDetectorTests {
    @Test func levelsAndPeriodicity() {
        let tone = Synth.voice(0.03, dbfs: -20)
        let frame = tone.withUnsafeBufferPointer { VoiceActivityDetector.analyze($0) }
        #expect(abs(Double(frame.dbfs) - -20) < 0.5)
        #expect(frame.periodicity > 0.9)
        let noise = Synth.noise(0.03, dbfs: -20)
        let noiseFrame = noise.withUnsafeBufferPointer { VoiceActivityDetector.analyze($0) }
        #expect(noiseFrame.periodicity < 0.4)
        let silent = [Float](repeating: 0, count: 480).withUnsafeBufferPointer { VoiceActivityDetector.analyze($0) }
        #expect(silent.dbfs == -120)
    }

    @Test func digitalSilenceIsNoSpeech() {
        let vad = detector(Synth.silence(3))
        #expect(!vad.speechDetected)
        #expect(vad.floorDbfs == -120)
        #expect(SilenceFilter.shouldSkipTranscription(vad.meta()))
    }

    @Test func roomNoiseIsNoSpeech() {
        let vad = detector(Synth.noise(5, dbfs: -50))
        #expect(!vad.speechDetected)
        #expect(SilenceFilter.shouldSkipTranscription(vad.meta()))
    }

    @Test func shortSpokenWordIsSpeech() {
        let vad = detector(Synth.withFloor(Synth.silence(1) + Synth.voice(0.35, dbfs: -28) + Synth.silence(1)))
        #expect(vad.speechDetected)
        #expect(!SilenceFilter.shouldSkipTranscription(vad.meta()))
    }

    @Test func quietSpeechInLoudRoomIsSpeech() {
        let signal = Synth.speech(2, dbfs: -30)
        let vad = detector(Synth.withFloor(Synth.silence(1) + signal + Synth.silence(1), dbfs: -48))
        #expect(vad.speechDetected)
    }

    @Test func clicksAreNoSpeech() {
        let vad = detector(Synth.withFloor(Synth.clicks(4)))
        #expect(!vad.speechDetected)
        #expect(vad.meta().voicedMs == 0)
    }

    @Test func singleBreathIsNoSpeech() {
        // Atemzug: 0,6 s aperiodisches Rauschen, deutlich über dem Grundrauschen.
        let breath = Synth.noise(0.6, dbfs: -32, seed: 3)
        let vad = detector(Synth.withFloor(Synth.silence(1.5) + breath + Synth.silence(1.5)))
        #expect(!vad.speechDetected)
        #expect(SilenceFilter.hasLowSpeechActivity(vad.meta()))
    }

    @Test func longContinuousSignals() {
        // Abschnitte länger als das 2,5-s-Fenster (Dauerton bzw. Dauerrauschen).
        #expect(detector(Synth.withFloor(Synth.silence(1) + Synth.voice(4, dbfs: -20) + Synth.silence(1))).speechDetected)
        #expect(!detector(Synth.withFloor(Synth.silence(1) + Synth.noise(4, dbfs: -30) + Synth.silence(1))).speechDetected)
        #expect(!VoiceActivityDetector.hasSyllabicBurst([(0, 200)]))
        #expect(VoiceActivityDetector.hasSyllabicBurst([(0, 200), (210, 12), (225, 12), (240, 12)]))
    }

    @Test func repeatedBreathingIsNoSpeech() {
        var audio: [Float] = []
        for seed in 1...6 { audio += Synth.noise(0.7, dbfs: -30, seed: UInt64(seed)) + Synth.silence(3) }
        #expect(!detector(Synth.withFloor(audio)).speechDetected)
    }

    @Test func sustainedWhisperIsSpeech() {
        // Flüstern: aperiodisch, aber über mehr als eine Sekunde in Silben.
        var whisper: [Float] = []
        for seed in 1...5 { whisper += Synth.noise(0.3, dbfs: -34, seed: UInt64(seed)) + Synth.silence(0.1) }
        let vad = detector(Synth.withFloor(Synth.silence(1) + whisper + Synth.silence(1)))
        #expect(vad.speechDetected)
    }

    @Test func blockSizeDoesNotMatter() {
        let signal = Synth.withFloor(Synth.silence(0.5) + Synth.speech(1.5) + Synth.silence(0.5))
        let a = detector(signal, block: 1_600)
        let b = detector(signal, block: 333)
        let c = detector(signal, block: signal.count)
        #expect(a.frames == b.frames && b.frames == c.frames)
    }

    @Test func earlySyllablesAreJudgedAgainstLaterFloor() {
        var vad = VoiceActivityDetector()
        for _ in 0..<15 { vad.appendFrame(dbfs: -25, periodicity: 0.9) }
        for _ in 0..<110 { vad.appendFrame(dbfs: -50, periodicity: 0) }
        #expect(abs(vad.floorDbfs - -50) < 0.01)
        #expect(vad.meta().speechMs == 450)
        #expect(vad.speechDetected)
    }

    @Test func onlyFramesStrictlyAboveFloorPlus15Count() {
        var vad = VoiceActivityDetector()
        for _ in 0..<100 { vad.appendFrame(dbfs: -50, periodicity: 0) }
        vad.appendFrame(dbfs: -35, periodicity: 0)
        vad.appendFrame(dbfs: -34, periodicity: 0)
        #expect(vad.meta().speechMs == 30)
    }

    @Test func percentileFloor() {
        var vad = VoiceActivityDetector()
        for i in 0..<100 { vad.appendFrame(dbfs: Float(-100 + i), periodicity: 0) }
        #expect(vad.floorDbfs == -86)
        #expect(vad.peakDbfs == -1)
        #expect(vad.meta().speechMs == 64 * 30) // absolute Untergrenze −65, strikt darüber
    }
}

@Suite struct ChunkPlannerTests {
    /// Speist Audio blockweise ein und sammelt die Schnitte.
    private func cuts(_ samples: [Float], planner: ChunkPlanner = ChunkPlanner()) -> (cuts: [Range<Int>], vad: VoiceActivityDetector) {
        var vad = VoiceActivityDetector()
        var planner = planner
        var result: [Range<Int>] = []
        var offset = 0
        while offset < samples.count {
            vad.process(Array(samples[offset..<min(offset + 1_600, samples.count)]))
            while let cut = planner.nextCut(vad) { result.append(cut) }
            offset += 1_600
        }
        return (result, vad)
    }

    private func seconds(_ frame: Int) -> Double { Double(frame) * VoiceActivityDetector.frameMs / 1000 }

    @Test func cutsInsideTheFirstLongPauseAfterTenSeconds() throws {
        let audio = Synth.withFloor(Synth.speech(12) + Synth.silence(0.8) + Synth.speech(5))
        let (cuts, _) = cuts(audio)
        #expect(cuts.count == 1)
        let cut = try #require(cuts.first)
        #expect(cut.lowerBound == 0)
        // Schnitt liegt in der Pause (12,0–12,8 s), nicht in einer Silbe.
        #expect(seconds(cut.upperBound) > 12.0 && seconds(cut.upperBound) < 12.8)
    }

    @Test func noCutBeforeTenSeconds() {
        let audio = Synth.withFloor(Synth.speech(8) + Synth.silence(1.0) + Synth.speech(6))
        #expect(cuts(audio).cuts.isEmpty)
    }

    @Test func gapsBetweenWordsNeverCut() {
        // 30 s Rede mit Wortlücken bis 0,3 s – auch die gelockerte Regel (0,4 s) greift nicht.
        let audio = Synth.withFloor(Synth.speech(30, gap: 0.3))
        #expect(cuts(audio).cuts.isEmpty)
    }

    @Test func relaxedPauseAfterTwentySeconds() throws {
        let audio = Synth.withFloor(Synth.speech(21) + Synth.silence(0.45) + Synth.speech(3))
        let (cuts, _) = cuts(audio)
        let cut = try #require(cuts.first)
        #expect(seconds(cut.upperBound) > 21.0 && seconds(cut.upperBound) < 21.45)
    }

    @Test func severalChunksAreContiguous() {
        var audio: [Float] = []
        for _ in 0..<4 { audio += Synth.speech(11) + Synth.silence(0.9) }
        let (cuts, _) = cuts(Synth.withFloor(audio))
        #expect(cuts.count == 4)
        for (a, b) in zip(cuts, cuts.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
    }

    @Test func silentStretchIsNotAChunk() {
        let audio = Synth.withFloor(Synth.silence(15))
        #expect(cuts(audio).cuts.isEmpty)
    }

    @Test func worksOverNoisyFloor() throws {
        let audio = Synth.withFloor(Synth.speech(12, dbfs: -22) + Synth.silence(0.8) + Synth.speech(4, dbfs: -22), dbfs: -45)
        let cut = try #require(cuts(audio).cuts.first)
        #expect(seconds(cut.upperBound) > 12.0 && seconds(cut.upperBound) < 12.8)
    }
}

@Suite struct AudioEncoderTests {
    @Test func flacIsLosslessAndSmallerThanWav() throws {
        let samples = AudioEncoder.int16(Synth.withFloor(Synth.speech(3)))
        let encoded = AudioEncoder.encode(samples)
        #expect(encoded.isFLAC)
        #expect(encoded.fileName == "audio.flac")
        #expect(encoded.data.count < AudioEncoder.wav(samples[...]).count)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-test-\(UUID().uuidString).flac")
        try encoded.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let decoded = Array(UnsafeBufferPointer(start: buffer.int16ChannelData![0], count: Int(buffer.frameLength)))
        #expect(decoded == samples)
    }

    @Test func wavHeader() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768]
        let data = AudioEncoder.wav(samples[...])
        #expect(data.count == 44 + 10)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data[8..<16] == Data("WAVEfmt ".utf8))
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 16_000)
        let last = data[52..<54].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        #expect(Int16(littleEndian: last) == -32768)
    }

    @Test func wavFallbackWhenRequested() {
        let encoded = AudioEncoder.encode([1, 2, 3], preferFLAC: false)
        #expect(!encoded.isFLAC && encoded.mimeType == "audio/wav" && encoded.data.count == 50)
    }

    @Test func emptyAudioFallsBackToWav() {
        #expect(!AudioEncoder.encode([]).isFLAC)
    }

    @Test func floatConversionClamps() {
        #expect(AudioEncoder.int16([0, 1, -1, 2, -2, .nan, 0.5]) == [0, 32767, -32768, 32767, -32768, 0, 16383])
    }
}
