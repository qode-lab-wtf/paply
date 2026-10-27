import AVFoundation
import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Speicher")
struct StoreTests {
    // MARK: Aufnahme und WAV

    @Test func captureWritesWAVAndPlaceholderSynchronously() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: start)
        #expect(thought.state == .recording)
        #expect(thought.id.hasPrefix("s_") && thought.id.count == 34)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("thoughts/\(thought.id)/thought.json").path))
        #expect(FileSafety.fileSize(writer.url) == WAVWriter.headerSize)

        for _ in 0..<10 { writer.append(StoreSupport.tone(seconds: 0.25)) }
        let durationMs = writer.close()
        #expect(durationMs == 2_500)
        #expect(writer.close() == 2_500) // mehrfach schließen ist harmlos
        try await store.finishCapture(thought.id, durationMs: durationMs)

        // neu laden: alles von der Platte
        let reloaded = try ThoughtStore(root: root)
        let saved = try #require(await reloaded.thought(thought.id))
        #expect(saved.state == .captured)
        #expect(saved.durationMs == 2_500)
        #expect(saved.createdAt == start)
        #expect(saved.rev == 2)
        let file = try AVAudioFile(forReading: try #require(await reloaded.audioURL(thought.id)))
        #expect(file.length == 40_000)
        #expect(file.fileFormat.sampleRate == 16_000)
        let values = try URL(fileURLWithPath: writer.url.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func wavHeaderIsPatchedEveryTwoSeconds() throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let url = root.appendingPathComponent("a.wav")
        let writer = try WAVWriter(url: url)
        writer.append(StoreSupport.tone(seconds: 2.5))
        // Queue abwarten, ohne zu schließen (wie ein Absturz direkt danach)
        writer.waitForPendingWrites()
        #expect(WAVWriter.headerDurationMs(url) == 2_500)
        _ = writer.close()
    }

    @Test func crashRecoveryRepairsHeaderAndOddByte() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let id: String
        do {
            let store = try ThoughtStore(root: root)
            let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
            id = thought.id
            _ = writer.close() // Kopf mit 0 Daten
            // Absturz: Daten ohne Kopf-Aktualisierung + ein halbes Sample
            let handle = try FileHandle(forWritingTo: writer.url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(count: 32_000 * 2 + 1))
            try handle.close()
        }
        let store = try ThoughtStore(root: root)
        let repaired = try await store.recover()
        #expect(repaired == [id])
        let thought = try #require(await store.thought(id))
        #expect(thought.state == .captured)
        #expect(thought.durationMs == 2_000)
        let wav = store.wavURL(id)
        #expect(FileSafety.fileSize(wav) == 44 + 64_000)
        #expect(WAVWriter.headerDurationMs(wav) == 2_000)
        #expect(try AVAudioFile(forReading: wav).length == 32_000)
    }

    @Test func recoveryRemovesPlaceholderWithoutSoundButNotActiveCapture() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let (old, oldWriter) = try await store.beginCapture(trigger: .control, at: Date())
        _ = oldWriter.close()
        // neuer Prozess: alter Platzhalter ohne Ton
        let restarted = try ThoughtStore(root: root)
        let (running, writer) = try await restarted.beginCapture(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.5))
        _ = try await restarted.recover()
        #expect(await restarted.thought(old.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: restarted.directory(old.id).path))
        #expect(await restarted.thought(running.id)?.state == .recording) // laufende Aufnahme unberührt
        _ = writer.close()
    }

    // MARK: Beschädigte Dateien

    @Test func damagedTopicsFallBackToPreviousGeneration() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let first = Topic(title: "Umzug", icon: .home, owner: .ai)
        let second = Topic(title: "Fluxo", icon: .code, owner: .ai)
        do {
            let store = try ThoughtStore(root: root)
            try await store.saveTopics([first])
            try await store.saveTopics([first, second])
        }
        try Data("{\"topics\": [kaputt".utf8).write(to: root.appendingPathComponent("topics.json"))
        let store = try ThoughtStore(root: root)
        #expect(await store.topics().map(\.title) == ["Umzug"]) // Vorgänger, nicht leer
        let damaged = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("damaged-") }
        #expect(damaged.count == 1)
        // wieder gültig geschrieben
        let reopened = try ThoughtStore(root: root)
        #expect(await reopened.topics().map(\.title) == ["Umzug"])
    }

    @Test func damagedTopicsWithoutPreviousAreKeptAside() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        try Data("nicht json".utf8).write(to: root.appendingPathComponent("topics.json"))
        let store = try ThoughtStore(root: root)
        #expect(await store.topics().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let damaged = try #require(names.first { $0.hasPrefix("damaged-") })
        #expect(try String(contentsOf: root.appendingPathComponent(damaged), encoding: .utf8) == "nicht json")
    }

    @Test func damagedThoughtIsRebuiltFromSourceAndSound() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let id: String
        do {
            let store = try ThoughtStore(root: root)
            let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
            id = thought.id
            writer.append(StoreSupport.tone(seconds: 1))
            try await store.finishCapture(id, durationMs: writer.close())
            try await store.saveSourceOnce(id, ThoughtSource(text: "hallo welt", sentences: [], model: "whisper-large-v3",
                                                             createdAt: Date(), languages: ["de"], audioSeconds: 1))
        }
        try Data("{\"id\":".utf8).write(to: root.appendingPathComponent("thoughts/\(id)/thought.json"))
        let store = try ThoughtStore(root: root)
        let rebuilt = try #require(await store.thought(id))
        #expect(rebuilt.state == .transcribed)
        #expect(rebuilt.audio?.file == "audio.wav")
        #expect(rebuilt.durationMs == 1_000)
        #expect(try await store.recover().contains(id))
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory(id).path)
        #expect(files.contains { $0.hasPrefix("damaged-") })
    }

    // MARK: Schreiben

    @Test func saveIsAtomicAndCountsRevisions() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let clock = TestClock()
        let store = try ThoughtStore(root: root, now: clock.function)
        var thought = StoreSupport.thought()
        try await store.save(thought)
        #expect(await store.thought(thought.id)?.rev == 2)
        thought.title = "Neu"
        try await store.save(thought)
        #expect(await store.thought(thought.id)?.rev == 3)
        let updated = try await store.update(thought.id) { $0.title = "Noch neuer"; $0.titleOwner = .user }
        #expect(updated?.rev == 4)
        #expect(updated?.updatedAt == clock.now)
        // unverändert: kein Schreiben, keine neue Revision
        #expect(try await store.update(thought.id) { _ in }?.rev == 4)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory(thought.id).path)
        #expect(leftovers == ["thought.json"])
        // Zeiten als ganze Millisekunden, Schlüssel camelCase
        let json = try String(contentsOf: root.appendingPathComponent("thoughts/\(thought.id)/thought.json"), encoding: .utf8)
        #expect(json.contains("\"createdAt\":\(ThoughtJSON.milliseconds(thought.createdAt)),"))
        #expect(json.contains("\"titleOwner\":\"user\""))
    }

    @Test func emptyStateRemovesThoughtCompletely() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
        _ = writer.close()
        var empty = thought
        empty.state = .empty
        empty.deletedAt = Date()
        try await store.save(empty) // so verwirft ThoughtCapture (H3) einen Platzhalter
        #expect(await store.thought(thought.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.directory(thought.id).path))
    }

    @Test func sourceIsWrittenOnlyOnce() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let thought = StoreSupport.thought(state: .captured)
        try await store.save(thought)
        let source = ThoughtSource(text: "eins", sentences: [.init(id: "\(thought.id)_s0", text: "eins")], model: "whisper-large-v3",
                                   createdAt: Date(), languages: ["de"], audioSeconds: 1)
        try await store.saveSourceOnce(thought.id, source)
        await #expect(throws: ThoughtStoreError.sourceExists) {
            try await store.saveSourceOnce(thought.id, ThoughtSource(text: "zwei", sentences: [], model: "x", createdAt: Date(),
                                                                     languages: [], audioSeconds: 1))
        }
        #expect(await (try ThoughtStore(root: root)).source(thought.id)?.text == "eins")
    }

    @Test func aiResultRoundTripsAllDecisions() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let thought = StoreSupport.thought(state: .structuring)
        try await store.save(thought)
        let decisions: [TopicDecision] = [.existing("t_1"), .new(name: "Garten", icon: .leaf), .none]
        for decision in decisions {
            let result = StructureResult(title: "T", cleanText: nil, topic: decision,
                                         tasks: [TaskDraft(text: "Anrufen", quote: "ich muss anrufen", dueHint: "morgen")],
                                         related: [RelatedDraft(thoughtID: "s_x", kind: .changes, reason: "Grund")], rejections: ["length"])
            try await store.saveAIResult(thought.id, AIResultRecord(result: result, model: "openai/gpt-oss-120b",
                                                                    usage: TokenUsage(prompt: 1, completion: 2, total: 3)))
            #expect(await store.aiResult(thought.id) == result)
            #expect(await store.aiResultRecord(thought.id)?.usage?.total == 3)
        }
        await store.discardAIResult(thought.id)
        #expect(await store.aiResult(thought.id) == nil)
    }

    @Test func changesAreBroadcastToEveryListener() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let a = store.changes, b = store.changes
        let thought = StoreSupport.thought()
        try await store.save(thought)
        try await store.saveTopics([])
        var ia = a.makeAsyncIterator(), ib = b.makeAsyncIterator()
        #expect(await ia.next() == thought.id)
        #expect(await ib.next() == thought.id)
        #expect(await ia.next() == ThoughtStore.topicsChangeID)
    }

    @Test func mergedTopicsResolveThroughAliasChain() {
        let a = Topic(id: "t_a", title: "Wohnung", icon: .home, owner: .ai, mergedInto: "t_b")
        let b = Topic(id: "t_b", title: "Umzug", icon: .home, owner: .ai, mergedInto: "t_c")
        let c = Topic(id: "t_c", title: "Umzug Bonn", icon: .home, owner: .user)
        #expect(ThoughtStore.resolve("t_a", in: [a, b, c])?.id == "t_c")
        #expect(ThoughtStore.resolve("t_x", in: [a, b, c]) == nil)
        let loop = Topic(id: "t_l", title: "L", icon: .home, owner: .ai, mergedInto: "t_l")
        #expect(ThoughtStore.resolve("t_l", in: [loop])?.id == "t_l")
    }

    // MARK: Aufbewahrung

    @Test func trashAndAudioRetention() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let clock = TestClock()
        let store = try ThoughtStore(root: root, now: clock.function)
        func captured(_ seconds: Double) async throws -> String {
            let (thought, writer) = try await store.beginCapture(trigger: .control, at: clock.now)
            writer.append(StoreSupport.tone(seconds: seconds))
            try await store.finishCapture(thought.id, durationMs: writer.close())
            return thought.id
        }
        let done = try await captured(0.5)
        let unprocessed = try await captured(0.5)
        let trashed = try await captured(0.5)
        try await store.saveSourceOnce(done, ThoughtSource(text: "x", sentences: [], model: "w", createdAt: clock.now, languages: [], audioSeconds: 0.5))
        let deleteAfter = clock.now.addingTimeInterval(AudioCompactor.audioRetention)
        try await store.update(done) { $0.state = .done; $0.audio?.deleteAfter = deleteAfter }
        try await store.update(unprocessed) { $0.audio?.deleteAfter = deleteAfter } // nie verschriftlicht
        try await store.delete(trashed)

        await store.housekeeping(now: clock.now.addingTimeInterval(29 * 86_400))
        #expect(await store.audioURL(done) != nil)
        #expect(await store.thought(trashed) != nil)

        await store.housekeeping(now: clock.now.addingTimeInterval(31 * 86_400))
        #expect(await store.audioURL(done) == nil)
        #expect(await store.thought(done)?.audio == nil)
        #expect(await store.audioURL(unprocessed) != nil) // nicht verarbeiteter Ton bleibt immer
        #expect(await store.thought(trashed) == nil) // „Zuletzt gelöscht“ nach 30 Tagen weg
    }

    @Test func compactionReplacesWAVWithM4A() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
        writer.append(StoreSupport.tone(seconds: 10))
        try await store.finishCapture(thought.id, durationMs: writer.close())
        let wavSize = FileSafety.fileSize(store.wavURL(thought.id)) ?? 0
        #expect(await store.compactAudioIfNeeded(thought.id) == false) // ohne Rohtext nie
        try await store.saveSourceOnce(thought.id, ThoughtSource(text: "x", sentences: [], model: "w", createdAt: Date(), languages: [], audioSeconds: 10))
        #expect(await store.compactAudioIfNeeded(thought.id))
        let url = try #require(await store.audioURL(thought.id))
        #expect(url.lastPathComponent == "audio.m4a")
        #expect(!FileManager.default.fileExists(atPath: store.wavURL(thought.id).path))
        let file = try AVAudioFile(forReading: url)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 10) < 0.2)
        #expect(Double(FileSafety.fileSize(url) ?? .max) < Double(wavSize) * 0.3) // 32 kbit/s statt 256
        #expect(FileSafety.readSamplesCount(url) > 150_000)
    }

    // MARK: Übernahme des S1-Rückfalls (H3)

    @Test func adoptsSpikeCaptureFilesInPlace() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        // Format von SpikeCaptureStore: JSONEncoder .millisecondsSince1970 (Bruchteile), WAV mit Kopf
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        var finished = Thought(createdAt: Date(timeIntervalSince1970: 1_793_000_000.1234), trigger: .control, state: .captured,
                               audio: Thought.AudioInfo(file: "audio.wav"), updatedAt: Date())
        finished.durationMs = 1_000
        let crashed = Thought(createdAt: Date(), trigger: .control, state: .recording, audio: Thought.AudioInfo(file: "audio.wav"), updatedAt: Date())
        for (thought, seconds) in [(finished, 1.0), (crashed, 0.5)] {
            let dir = root.appendingPathComponent("thoughts/\(thought.id)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(thought).write(to: dir.appendingPathComponent("thought.json"))
            let samples = AudioEncoder.int16(StoreSupport.tone(seconds: seconds))
            var wav = AudioEncoder.wav(samples[...])
            if thought.state == .recording { wav.replaceSubrange(40..<44, with: Data(count: 4)) } // Kopf nie geschlossen
            try wav.write(to: dir.appendingPathComponent("audio.wav"))
        }
        let store = try ThoughtStore(root: root)
        #expect(try await store.recover() == [crashed.id])
        #expect(await store.thought(finished.id)?.state == .captured)
        #expect(await store.thought(finished.id)?.durationMs == 1_000)
        #expect(await store.thought(crashed.id)?.state == .captured)
        #expect(await store.thought(crashed.id)?.durationMs == 500)
        #expect(await store.audioURL(finished.id) != nil)
    }

    // MARK: Leistung (KONZEPT §3.1: 2 000 Gedanken laden < 300 ms)

    @Test func loadsTwoThousandThoughtsQuickly() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        try StoreSupport.writeCorpus(count: 2_000, to: root)
        let clock = ContinuousClock()
        var elapsed = Duration.seconds(10)
        for _ in 0..<6 { // bestes von sechs frischen Speichern, verteilt (andere Tests laufen parallel)
            try await Task.sleep(for: .milliseconds(150))
            let store = try ThoughtStore(root: root)
            let started = clock.now
            let all = await store.all()
            elapsed = min(elapsed, clock.now - started)
            #expect(all.count == 2_000)
        }
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("Leistung: 2 000 Gedanken laden \(Int(ms)) ms")
        #expect(ms < 300)
    }
}

extension StoreSupport {
    /// Realistische Ablage: Titel, 2–4 Sätze Text, Aufgaben, Verbindungen (≈ 1,5 KB je Datei).
    static func writeCorpus(count: Int, to root: URL) throws {
        let words = ["Wohnung", "Umzug", "Fluxo", "Beta", "Kita", "Garten", "Tomaten", "Halbmarathon", "Laufen", "Budget",
                     "Familie", "Jana", "Mila", "Ben", "Porto", "Lissabon", "Flug", "Hotel", "Steuer", "Rechnung", "Investor",
                     "Pitch", "Retention", "Android", "Kategorien", "Supabase", "Release", "Gitarre", "Akkorde", "Buch"]
        let encoder = ThoughtJSON.encoder()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var previous: String?
        for i in 0..<count {
            func w(_ k: Int) -> String { words[(i * 7 + k * 13) % words.count] }
            var thought = thought(createdAt: base.addingTimeInterval(Double(i) * 3_600),
                                  title: "\(w(1)) und \(w(2)) planen",
                                  text: "Heute über \(w(1)) nachgedacht: \(w(3)) und \(w(4)) hängen zusammen. Bis Freitag \(w(5)) klären, "
                                      + "danach \(w(6)) mit \(w(7)) besprechen. Ärger mit der Straße vermeiden, Café am Ende.",
                                  topicId: "t_\(i % 20)")
            thought.tasks = [ThoughtTask(text: "\(w(5)) klären", quote: "bis freitag \(w(5)) klären", dueHint: "bis Freitag", owner: .ai)]
            if let previous { thought.links = [ThoughtLink(target: previous, kind: .continues, reason: "Gleiches Vorhaben", origin: .ai)] }
            thought.keywords = [w(1), w(2), w(3)].map { $0.lowercased() }
            let dir = root.appendingPathComponent("thoughts/\(thought.id)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(thought).write(to: dir.appendingPathComponent("thought.json"))
            previous = thought.id
        }
    }
}

extension FileSafety {
    static func readSamplesCount(_ url: URL) -> Int {
        FileTranscriber.readSamples(url)?.count ?? 0
    }
}
