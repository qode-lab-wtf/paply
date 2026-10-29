import AVFoundation
import Foundation

public actor ConversationStore: ConversationRecordingStore {
    public nonisolated let root: URL
    private var cache: [String: Conversation] = [:]
    private var loaded = false
    private let broadcast = Broadcast<String>()
    public nonisolated var changes: AsyncStream<String> { broadcast.stream }
    public init(root: URL) { self.root = root }
    public nonisolated func directory(_ id: String) -> URL { root.appendingPathComponent("conversations").appendingPathComponent(id) }
    public nonisolated func workDirectory(_ id: String) -> URL { directory(id).appendingPathComponent("work") }
    public nonisolated func wavURL(_ id: String) -> URL { directory(id).appendingPathComponent("audio.wav") }
    private func check(_ id: String) throws { guard ThoughtStore.isValidID(id) else { throw ThoughtStoreError.invalidID } }
    public func load() throws {
        guard !loaded else { return }
        guard root.isFileURL else { throw ThoughtStoreError.unavailable }
        let base = root.appendingPathComponent("conversations")
        try FileSafety.createDirectory(base)
        for dir in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) where ThoughtStore.isValidID(dir.lastPathComponent) {
            let id = dir.lastPathComponent
            guard cache[id] == nil else { continue }
            do {
                let file = dir.appendingPathComponent("conversation.json")
                var item: Conversation
                let data = FileSafety.exists(file) ? try Data(contentsOf: file) : nil
                if let data, let decoded = try? ThoughtJSON.decoder().decode(Conversation.self, from: data) {
                    item = decoded
                } else {
                    // Beschädigtes behalten; Ton ist die letzte verlässliche Quelle.
                    if FileSafety.exists(file) {
                        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("damaged-" + UUID().uuidString + ".json"))
                    }
                    guard FileSafety.exists(wavURL(id)) else { throw ThoughtStoreError.notFound }
                    item = Conversation(id: id, durationMs: try WAVWriter.repair(wavURL(id)), origin: .recording, trigger: .unknown, state: .captured, audio: .init(file: "audio.wav"))
                    try write(item)
                }
                guard item.id == id else { throw ThoughtStoreError.invalidID }
                if item.state == .recording {
                    item.durationMs = try WAVWriter.repair(wavURL(id)); item.state = .captured
                    item.rev += 1; item.updatedAt = Date()
                    try write(item)
                } else if item.state == .analyzing { item.state = .captured; try write(item) }
                cache[id] = item
            } catch {
                let quarantine = root.appendingPathComponent("quarantine")
                try FileSafety.createDirectory(quarantine)
                try? FileManager.default.moveItem(at: dir, to: quarantine.appendingPathComponent(id + "-" + UUID().uuidString))
            }
        }
        loaded = true
    }
    public func all() throws -> [Conversation] { try load(); return cache.values.sorted { $0.createdAt > $1.createdAt } }
    public func conversation(_ id: String) throws -> Conversation? { try check(id); try load(); return cache[id] }
    public func transcript(_ id: String) throws -> ConversationTranscript? {
        try check(id)
        let file = directory(id).appendingPathComponent("transcript.json")
        guard FileSafety.exists(file) else { return nil }
        return try ThoughtJSON.decoder().decode(ConversationTranscript.self, from: Data(contentsOf: file))
    }
    public func saveTranscript(_ transcript: ConversationTranscript, for id: String) throws {
        try check(id)
        var next = transcript
        if let old = try self.transcript(id) {
            for i in next.utterances.indices {
                if next.utterances[i].speakerOwner != .user, let user = old.utterances.first(where: { $0.speakerOwner == .user && ConversationUtteranceMatch.matches($0, next.utterances[i]) }) { next.utterances[i].speakerID = user.speakerID; next.utterances[i].speakerOwner = .user }
            }
        }
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(next), to: directory(id).appendingPathComponent("transcript.json"))
    }
    public func voiceprints(_ id: String) throws -> [String: VoicePrint] {
        try check(id)
        let file = directory(id).appendingPathComponent("voiceprints.json")
        guard FileSafety.exists(file) else { return [:] }
        return try ThoughtJSON.decoder().decode([String: VoicePrint].self, from: Data(contentsOf: file))
    }
    public func saveVoiceprints(_ prints: [String: VoicePrint], for id: String) throws {
        try check(id)
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(prints), to: directory(id).appendingPathComponent("voiceprints.json"))
    }
    private func write(_ item: Conversation) throws {
        try FileSafety.createDirectory(directory(item.id))
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(item), to: directory(item.id).appendingPathComponent("conversation.json"))
    }
    public func save(_ item: Conversation) throws {
        try check(item.id); try load()
        var next = item
        next.rev = max(cache[item.id]?.rev ?? 0, item.rev) + 1; next.updatedAt = Date()
        try write(next); cache[next.id] = next; broadcast.yield(next.id)
    }
    @discardableResult public func update(_ id: String, _ change: @Sendable (inout Conversation) -> Void) throws -> Conversation? {
        guard var item = try conversation(id) else { return nil }
        change(&item); item.id = id
        try save(item)
        return cache[id]
    }
    public func beginRecording(trigger: ThoughtTrigger, at: Date) throws -> (conversation: Conversation, audio: WAVWriter) {
        try load()
        guard !cache.values.contains(where: { $0.state == .recording }) else { throw ThoughtStoreError.unavailable }
        let item = Conversation(createdAt: at, origin: .recording, trigger: trigger, state: .recording, audio: .init(file: "audio.wav"))
        do {
            try save(item)
            let writer = try WAVWriter(url: wavURL(item.id))
            return (cache[item.id]!, writer)
        } catch {
            cache[item.id] = nil
            try? FileManager.default.removeItem(at: directory(item.id))
            throw error
        }
    }
    public func finishRecording(_ id: String, durationMs: Int, gaps: [ConversationGap]) throws -> Conversation? {
        do {
            return try update(id) { $0.durationMs = durationMs; $0.gaps = gaps; $0.state = .captured }
        } catch {
            cache[id]?.state = .needsAttention
            if let item = cache[id] { try? write(item) }
            throw error
        }
    }
    public func discardRecording(_ id: String) {
        try? update(id) { $0.state = .captured; $0.deletedAt = Date() }
    }
    public func delete(_ id: String) throws { try update(id) { if $0.deletedAt == nil { $0.deletedAt = Date() } } }
    public func restore(_ id: String) throws { try update(id) { $0.deletedAt = nil } }
    public func purge(_ id: String) async throws {
        try check(id); try load()
        let trash = root.appendingPathComponent(".purge-" + UUID().uuidString)
        if FileSafety.exists(directory(id)) { try FileManager.default.moveItem(at: directory(id), to: trash) }
        cache[id] = nil; broadcast.yield(id)
        try await Task.detached(priority: .utility) {
            if FileSafety.exists(trash) { try FileManager.default.removeItem(at: trash) }
        }.value
    }
    public func audioURL(_ id: String) throws -> URL? {
        guard let item = try conversation(id), let file = item.audio?.file, ["audio.wav", "audio.m4a"].contains(file) else { return nil }
        let url = directory(id).appendingPathComponent(file)
        return FileSafety.exists(url) ? url : nil
    }
    public func importAudio(from url: URL, at: Date) async throws -> Conversation {
        try load()
        let item = Conversation(createdAt: at, origin: .imported, trigger: .app, state: .captured, audio: .init(file: "audio.wav"))
        let temporary = root.appendingPathComponent(".import-" + UUID().uuidString)
        let destination = directory(item.id)
        let volume = root
        defer { try? FileManager.default.removeItem(at: temporary) }
        let imported = try await Task.detached(priority: .utility) {
            var item = item
            let input = try AVAudioFile(forReading: url)
            let required = Int64(Double(input.length) / input.processingFormat.sampleRate * 32000) + Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) + 200_000_000
            let available = (try FileManager.default.attributesOfFileSystem(forPath: volume.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard available >= required else { throw ThoughtStoreError.unavailable }
            try FileSafety.createDirectory(temporary)
            let original = temporary.appendingPathComponent("import-original." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: original)
            FileSafety.applyProtection(original); FileSafety.excludeFromBackup(original)
            let converted = try ConversationAudio.convert(original, to: temporary.appendingPathComponent("audio.wav"))
            item.durationMs = converted.durationMs
            if converted.distinctStereo { item.expectedSpeakers = 2 } else { try FileManager.default.removeItem(at: original) }
            try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(item), to: temporary.appendingPathComponent("conversation.json"))
            return item
        }.value
        try FileManager.default.moveItem(at: temporary, to: destination)
        cache[imported.id] = imported; broadcast.yield(imported.id)
        return imported
    }
    public func prepareForAnalysis(_ id: String) async throws -> URL? {
        guard let url = try audioURL(id) else { return nil }
        if url.pathExtension == "m4a" {
            let target = wavURL(id)
            let temporary = root.appendingPathComponent(".prepare-" + UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: temporary) }
            _ = try await Task.detached(priority: .utility) { try ConversationAudio.convert(url, to: temporary) }.value
            guard cache[id]?.deletedAt == nil, cache[id] != nil else { return nil }
            if FileSafety.exists(target) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temporary, to: target)
            try update(id) { $0.audio = .init(file: "audio.wav") }
        }
        return wavURL(id)
    }
    public func compactAudio(_ id: String) async throws {
        guard let item = try conversation(id), item.state == .done, item.audio?.file == "audio.wav" else { return }
        let target = directory(id).appendingPathComponent("audio.m4a")
        let source = wavURL(id)
        let temporary = root.appendingPathComponent(".compact-" + UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await Task.detached(priority: .utility) { try ConversationAudio.compress(source, to: temporary) }.value
        guard cache[id]?.deletedAt == nil, cache[id] != nil else { return }
        if FileSafety.exists(target) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
        try update(id) { $0.audio = .init(file: "audio.m4a") }
        try FileManager.default.removeItem(at: wavURL(id))
        let work = workDirectory(id)
        let trash = root.appendingPathComponent(".work-" + UUID().uuidString)
        if FileSafety.exists(work) {
            try FileManager.default.moveItem(at: work, to: trash)
            try await Task.detached(priority: .utility) { try FileManager.default.removeItem(at: trash) }.value
        }
    }
    public func housekeeping(now: Date = Date()) async throws {
        for item in try all() {
            if let deleted = item.deletedAt, now.timeIntervalSince(deleted) >= 30 * 86400 { try await purge(item.id); continue }
            guard item.state == .done, now.timeIntervalSince(item.createdAt) >= 30 * 86400 else { continue }
            guard cache[item.id]?.state == .done else { continue }
            let trash = root.appendingPathComponent(".expired-" + UUID().uuidString)
            try FileSafety.createDirectory(trash)
            for file in try FileManager.default.contentsOfDirectory(at: directory(item.id), includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("audio.") || file.lastPathComponent.hasPrefix("import-original.") {
                try FileManager.default.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent))
            }
            try update(item.id) { $0.audio = nil }
            try await Task.detached(priority: .utility) { try FileManager.default.removeItem(at: trash) }.value
        }
    }
}

/// Blockweise Umwandlung; auch mehrstündige Importe passen in den Speicher.
enum ConversationAudio {
    static func convert(_ source: URL, to target: URL) throws -> (durationMs: Int, distinctStereo: Bool) {
        let input = try AVAudioFile(forReading: source)
        if input.processingFormat.sampleRate == 16000 && input.processingFormat.channelCount == 1 {
            let writer = try WAVWriter(url: target)
            defer { _ = writer.close() }
            let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192)!
            while input.framePosition < input.length {
                try input.read(into: buffer)
                guard let data = buffer.floatChannelData else { throw ThoughtStoreError.unavailable }
                writer.append(Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))))
                writer.waitForPendingWrites()
                if writer.hasFailed { throw ThoughtStoreError.unavailable }
            }
            return (writer.close(), false)
        }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw ThoughtStoreError.unavailable }
        let writer = try WAVWriter(url: target)
        defer { _ = writer.close() }
        var difference = 0.0, energy = 0.0
        while true {
            var failure: NSError?
            var readError: Error?
            let status = converter.convert(to: outBuffer, error: &failure) { count, state in
                do {
                    guard input.framePosition < input.length else { state.pointee = .endOfStream; return nil }
                    try input.read(into: inBuffer, frameCount: min(count, inBuffer.frameCapacity))
                    if inBuffer.frameLength == 0 { state.pointee = .endOfStream; return nil }
                    if input.processingFormat.channelCount == 2, let channels = inBuffer.floatChannelData {
                        for i in 0..<Int(inBuffer.frameLength) {
                            let a = Double(channels[0][i]), b = Double(channels[1][i])
                            difference += (a - b) * (a - b); energy += a * a + b * b
                        }
                    }
                    state.pointee = .haveData; return inBuffer
                } catch { readError = error; state.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }; if let failure { throw failure }
            if let data = outBuffer.floatChannelData, outBuffer.frameLength > 0 {
                writer.append(Array(UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength))))
                writer.waitForPendingWrites()
                if writer.hasFailed { throw ThoughtStoreError.unavailable }
            }
            if status == .endOfStream { break }
            if status == .error { throw ThoughtStoreError.unavailable }
        }
        return (writer.close(), energy > 0.001 && difference / energy > 0.25)
    }
    static func compress(_ source: URL, to target: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".tmp-" + UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        let output = try AVAudioFile(forWriting: temp, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000])
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192)!
        while input.framePosition < input.length { try input.read(into: buffer); try output.write(from: buffer) }
        output.close()
        try FileSafety.writeAtomically(Data(contentsOf: temp), to: target)
        FileSafety.excludeFromBackup(target)
    }
}
