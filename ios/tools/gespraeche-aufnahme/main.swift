import AVFoundation
import Foundation

// Der Test hängt keinen Pegel-Kanal an; die echte Datei bleibt unangetastet.
final class LevelChannel {
    static func tag(for owner: String) -> UInt64 { 0 }
    func begin(tag: UInt64) {}
    func push(level: Float, ns: UInt64) {}
}
final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var blocks: [[Float]] = []
    func add(_ samples: [Float]) {
        lock.lock()
        blocks.append(samples)
        lock.unlock()
    }
    var value: [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return blocks
    }
}
func buffer(_ rate: Double) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let value = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
    value.frameLength = 4800
    for i in 0..<4800 { value.floatChannelData![0][i] = sin(Float(i) * 0.07) * 0.2 }
    return value
}
let plain = AudioTapProcessor()
let parallel = AudioTapProcessor()
let baseline = Received()
let dictation = Received()
let conversation = Received()
let baselineRestarts = Received()
let parallelRestarts = Received()
parallel.attachListener(owner: "conversation") { conversation.add($0) }
func feed(_ rate: Double = 48_000) {
    let input = buffer(rate)
    plain.process(input, arrivalNs: MonoClock.now())
    parallel.process(input, arrivalNs: MonoClock.now())
}
feed()
precondition(conversation.value.count == 1)
plain.attach(owner: "dictation", sink: { baseline.add($0) }, levels: nil)
parallel.attach(owner: "dictation", sink: { dictation.add($0) }, levels: nil)
precondition(conversation.value.count == 1, "Kein Vorlauf an den Mithörer")
feed()
plain.detach(owner: "dictation")
parallel.detach(owner: "dictation")
feed()
precondition(conversation.value.count == 3, "Mithörer bleibt nach Diktat-Ende")
plain.attach(owner: "thought", sink: { baseline.add($0) }, levels: nil, onRestart: { baselineRestarts.add([]) })
parallel.attach(owner: "thought", sink: { dictation.add($0) }, levels: nil, onRestart: { parallelRestarts.add([]) })
feed()
plain.prepareSilenceRestart()
parallel.prepareSilenceRestart()
plain.reset()
parallel.reset()
feed(44_100)
precondition(conversation.value.count == 5, "Mithörer überlebt Neustart und Formatwechsel")
parallel.detachListener(owner: "stale")
feed()
precondition(conversation.value.count == 6, "Fremde ID löst nicht")
parallel.detachListener(owner: "conversation")
feed()
precondition(conversation.value.count == 6, "Nach Lösen kein Zulauf")
precondition(baselineRestarts.value.count == 1 && baselineRestarts.value == parallelRestarts.value, "Neustart-Haken unverändert")
precondition(baseline.value == dictation.value, "Diktat/Gedanke müssen samplegleich bleiben")
print("Tap: Diktat samplegleich; Mithörer unabhängig, Neustart und Formatwechsel grün.")
