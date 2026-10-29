import Foundation
@preconcurrency import AVFoundation
import PaplyKit

/// PLATZHALTER: Bei der Zusammenführung durch den PaplyKit-Speicher ersetzen.
/// Eigener Ordner verhindert, dass die vorläufige Ablage echte Daten überschreibt.
actor RecordingStoreStub: ConversationRecordingStore {
    private let root = URL.applicationSupportDirectory.appendingPathComponent("Gespraeche-Aufnahme-Stub")
    private func directory(_ id: String) -> URL { root.appendingPathComponent(id) }
    private func save(_ value: Conversation) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(value).write(to: directory(value.id).appendingPathComponent("conversation.json"), options: .atomic)
    }
    private func read(_ id: String) throws -> Conversation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Conversation.self, from: Data(contentsOf: directory(id).appendingPathComponent("conversation.json")))
    }
    func beginRecording(trigger: ThoughtTrigger, at: Date) async throws -> (conversation: Conversation, audio: WAVWriter) {
        let value = Conversation(id: UUID().uuidString, createdAt: at, origin: .recording, trigger: trigger, state: .recording)
        try FileManager.default.createDirectory(at: directory(value.id), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try save(value)
        let writer = try WAVWriter(url: directory(value.id).appendingPathComponent("audio.wav"))
        return (value, writer)
    }
    func finishRecording(_ id: String, durationMs: Int, gaps: [ConversationGap]) async throws -> Conversation? {
        var value = try read(id)
        value.durationMs = durationMs
        value.gaps = gaps
        value.state = .captured
        value.rev += 1
        value.updatedAt = Date()
        try save(value)
        return value
    }
    func discardRecording(_ id: String) async {
        guard var value = try? read(id) else { return }
        value.deletedAt = Date()
        try? save(value)
    }
    func importAudio(from url: URL, at: Date) async throws -> Conversation {
        let input = try AVAudioFile(forReading: url)
        let (original, writer) = try await beginRecording(trigger: .app, at: at)
        do {
            let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: input.processingFormat, to: output),
                  let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 16_000) else { throw WAVWriter.WAVError.create }
            var queuedMs = 0
            while true {
                var error: NSError?
                let result = converter.convert(to: buffer, error: &error) { count, status in
                    guard let source = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: count) else {
                        status.pointee = .endOfStream
                        return nil
                    }
                    do { try input.read(into: source) } catch {
                        status.pointee = .noDataNow
                        return nil
                    }
                    status.pointee = source.frameLength == 0 ? .endOfStream : .haveData
                    return source.frameLength == 0 ? nil : source
                }
                if let error { throw error }
                if result == .error || result == .inputRanDry { throw WAVWriter.WAVError.notWAV }
                if buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] {
                    writer.append(Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))))
                    queuedMs += Int(buffer.frameLength) * 1000 / 16_000
                    // Import höchstens zwei Sekunden vor dem Schreiber halten.
                    while queuedMs - writer.durationMs > 2000, !writer.hasFailed {
                        try await Task.sleep(for: .milliseconds(10))
                    }
                }
                if writer.hasFailed { throw WAVWriter.WAVError.create }
                if result == .endOfStream { break }
            }
            var value = original
            value.durationMs = writer.close()
            value.state = .captured
            value.origin = .imported
            value.expectedSpeakers = input.processingFormat.channelCount == 2 ? 2 : nil
            try save(value)
            return value
        } catch {
            _ = writer.close()
            await discardRecording(original.id)
            throw error
        }
    }
}
