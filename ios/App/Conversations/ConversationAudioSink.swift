import Foundation
import PaplyKit

/// Zulauf nur fürs Gespräch. Der Tap reicht denselben Block weiter; WAVWriter schreibt auf seiner Queue.
final class ConversationAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: WAVWriter
    private var paused = false
    private var samples = 0
    private var currentLevel: Float = 0
    init(writer: WAVWriter) { self.writer = writer }
    func append(_ block: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard !paused else { return }
        writer.append(block)
        samples += block.count
        let peak = block.reduce(Float(0)) { max($0, abs($1)) }
        currentLevel = min(1, peak * 4)
    }
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return currentLevel
    }
    /// Liefert die exakte Dateiposition auch vor dem Schreiben der letzten Blöcke.
    func pause() -> Double {
        lock.lock()
        defer { lock.unlock() }
        paused = true
        currentLevel = 0
        return Double(samples) / 16_000
    }
    func resume() {
        lock.lock()
        paused = false
        lock.unlock()
    }
}
