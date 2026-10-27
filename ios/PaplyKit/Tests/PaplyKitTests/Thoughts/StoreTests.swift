import AVFoundation
import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Speicher")
struct StoreTests {
    // MARK: Geschützte Dateien (B1), Endgültig löschen (W1), Verwerfen (W2)

    private static func setPermissions(_ mode: Int, _ urls: [URL]) {
        for url in urls { try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
    }

    /// B1: Vor dem ersten Entsperren nicht lesbar → kein leerer Index für die ganze Laufzeit, `topics.json`
    /// bleibt unberührt; nach dem Entsperren lädt der Speicher nach und meldet es.
    @Test func protectedFilesAreLoadedLaterAndNeverOverwritten() async throws {
        let root = StoreSupport.temporaryRoot()
        let first = try ThoughtStore(root: root)
        let thought = StoreSupport.thought(title: "Tomaten gießen", text: "Die Tomaten gießen.")
        try await first.save(thought)
        try await first.saveTopics([Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .user)])
        let thoughtFile = first.directory(thought.id).appendingPathComponent("thought.json")
        let topicsFile = root.appendingPathComponent("topics.json")
        let topicsBefore = try Data(contentsOf: topicsFile)
        Self.setPermissions(0o000, [thoughtFile, topicsFile])
        defer {
            Self.setPermissions(0o644, [thoughtFile, topicsFile])
            StoreSupport.remove(root)
        }

        let locked = try ThoughtStore(root: root)
        #expect(await locked.all().isEmpty)
        #expect(await locked.topics().isEmpty)
        await #expect(throws: ThoughtStoreError.unavailable) {
            try await locked.saveTopics([Topic(id: "t_neu", title: "Neu", icon: .leaf, owner: .ai)])
        }
        await #expect(throws: ThoughtStoreError.unavailable) { try await locked.updateTopics { $0.removeAll() } }
        #expect(await locked.reloadIfNeeded() == false)
        // nichts rekonstruiert, nichts als beschädigt beiseitegelegt
        let rest = try FileManager.default.contentsOfDirectory(atPath: first.directory(thought.id).path)
        #expect(rest.contains("thought.json") && !rest.contains { $0.hasPrefix("damaged-") })

        var changes = locked.changes.makeAsyncIterator()
        Self.setPermissions(0o644, [thoughtFile, topicsFile])               // erstes Entsperren
        #expect(await locked.reloadIfNeeded())
        #expect(await locked.thought(thought.id)?.title == "Tomaten gießen")
        #expect(await locked.topics().map(\.id) == ["t_garden"])
        #expect(try Data(contentsOf: topicsFile) == topicsBefore)
        var seen: [String] = []
        while seen.count < 2, let change = await changes.next() { seen.append(change) }
        #expect(Set(seen) == [thought.id, ThoughtStore.topicsChangeID])
        // danach normal beschreibbar
        try await locked.saveTopics([Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .user),
                                     Topic(id: "t_neu", title: "Neu", icon: .leaf, owner: .ai)])
        #expect(await locked.topics().count == 2)
    }

    /// Vierte Prüfrunde (B): Themenliste und „vollständig gelesen“ kommen aus einem Aufruf. Geschützt ist die Liste
    /// leer und nie vollständig; nach dem Entsperren passen beide zusammen – nie „vollständig und leer“, solange
    /// `topics.json` ein Thema trägt.
    @Test func topicsSnapshotIsCompleteOnlyWhenRead() async throws {
        let root = StoreSupport.temporaryRoot()
        let first = try ThoughtStore(root: root)
        try await first.saveTopics([Topic(id: "t_saved", title: "Garten", icon: .leaf, owner: .user)])
        let topicsFile = root.appendingPathComponent("topics.json")
        Self.setPermissions(0o000, [topicsFile])
        defer {
            Self.setPermissions(0o644, [topicsFile])
            StoreSupport.remove(root)
        }
        let locked = try ThoughtStore(root: root)
        let before = await locked.topicsSnapshot()
        #expect(before.topics.isEmpty && !before.complete)
        Self.setPermissions(0o644, [topicsFile])                             // erstes Entsperren
        let after = await locked.topicsSnapshot()
        #expect(after.topics.map(\.id) == ["t_saved"] && after.complete)
    }

    /// Vierte Prüfrunde (B): Gespeichert entfernte Themen werden gemeldet (Themenbilder löschen nur darauf) –
    /// gelöscht, mangels Gedanken aufgeräumt; zusammengeführte (Alias) nicht.
    @Test func removedTopicsAreReportedAfterSaving() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        var removed = store.removedTopics.makeAsyncIterator()
        try await store.saveTopics([Topic(id: "t_a", title: "A", icon: .leaf, owner: .user),
                                    Topic(id: "t_b", title: "B", icon: .leaf, owner: .user),
                                    Topic(id: "t_c", title: "C", icon: .leaf, owner: .ai)])
        // zusammenführen: kein Entfernen
        try await store.updateTopics { topics in
            if let i = topics.firstIndex(where: { $0.id == "t_a" }) { topics[i].mergedInto = "t_b" }
        }
        // löschen (samt Alias)
        try await store.updateTopics { $0.removeAll { $0.id == "t_a" || $0.id == "t_b" } }
        #expect(await removed.next() == ["t_a", "t_b"])
        // letzter Gedanke endgültig gelöscht: Thema aufgeräumt
        let last = StoreSupport.thought(topicId: "t_c")
        try await store.save(last)
        await store.purge(last.id)
        #expect(await removed.next() == ["t_c"])
        #expect(await store.topics().isEmpty)
    }

    /// B1: Auch ohne ausdrücklichen Aufruf lädt der nächste Zugriff nach, sobald die Dateien lesbar sind.
    @Test func nextAccessRetriesAfterUnreadableDirectory() async throws {
        let root = StoreSupport.temporaryRoot()
        let first = try ThoughtStore(root: root)
        let thought = StoreSupport.thought(title: "Lampen bestellen")
        try await first.save(thought)
        let directory = first.thoughtsDirectory
        Self.setPermissions(0o000, [directory])
        defer {
            Self.setPermissions(0o755, [directory])
            StoreSupport.remove(root)
        }
        let locked = try ThoughtStore(root: root)
        #expect(await locked.all().isEmpty)
        Self.setPermissions(0o755, [directory])
        #expect(await locked.all().map(\.id) == [thought.id])
    }

    /// W1: Nach dem endgültigen Löschen legt `saveSourceOnce` keinen Ordner mehr an.
    @Test func sourceForAPurgedThoughtIsRejected() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let thought = StoreSupport.thought(state: .transcribing)
        try await store.save(thought)
        await store.purge(thought.id)
        let source = ThoughtSource(text: "Hallo", sentences: [], model: "whisper-large-v3", createdAt: Date(),
                                   languages: ["de"], audioSeconds: 1)
        await #expect(throws: ThoughtStoreError.notFound) { try await store.saveSourceOnce(thought.id, source) }
        #expect(!FileManager.default.fileExists(atPath: store.directory(thought.id).path))
        #expect(await (try ThoughtStore(root: root)).thought(thought.id) == nil)
    }

    /// W2: `finishCapture(_:durationMs:deletedAt:)` ein Schritt; ohne Ton weg, unbekannt → `.notFound`.
    @Test func finishCaptureWithDeletion() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let at = Date(timeIntervalSince1970: 1_793_093_400)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: at)
        writer.append(StoreSupport.tone(seconds: 1))
        let duration = writer.close()
        try await store.finishCapture(thought.id, durationMs: duration, deletedAt: at)
        let saved = try #require(await store.thought(thought.id))
        #expect(saved.state == .captured && saved.deletedAt == at && saved.durationMs == duration && saved.rev == 2)
        await #expect(throws: ThoughtStoreError.notFound) {
            try await store.finishCapture("s_gibtsnicht", durationMs: 1_000, deletedAt: at)
        }
        let (empty, emptyWriter) = try await store.beginCapture(trigger: .control, at: at)
        _ = emptyWriter.close()
        try await store.finishCapture(empty.id, durationMs: 0, deletedAt: at)
        #expect(await store.thought(empty.id) == nil)
    }

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

    @Test func damagedThoughtIsRebuiltFromSourceOrSound() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let transcribed: String, soundOnly: String
        do {
            let store = try ThoughtStore(root: root)
            func capture() async throws -> String {
                let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
                writer.append(StoreSupport.tone(seconds: 1))
                try await store.finishCapture(thought.id, durationMs: writer.close())
                return thought.id
            }
            transcribed = try await capture()
            soundOnly = try await capture() // nie verschriftlicht
            try await store.saveSourceOnce(transcribed, ThoughtSource(text: "hallo welt", sentences: [], model: "whisper-large-v3",
                                                                      createdAt: Date(), languages: ["de"], audioSeconds: 1))
        }
        for id in [transcribed, soundOnly] {
            try Data("{\"id\":".utf8).write(to: root.appendingPathComponent("thoughts/\(id)/thought.json"))
        }
        let store = try ThoughtStore(root: root)
        let fromSource = try #require(await store.thought(transcribed))
        #expect(fromSource.state == .transcribed)
        #expect(fromSource.audio == nil) // Ton ging schon mit dem Rohtext
        #expect(fromSource.durationMs == 1_000)
        let fromSound = try #require(await store.thought(soundOnly))
        #expect(fromSound.state == .captured)
        #expect(fromSound.audio?.file == "audio.wav")
        #expect(fromSound.durationMs == 1_000)
        let recovered = try await store.recover()
        #expect(recovered.contains(transcribed) && recovered.contains(soundOnly))
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory(transcribed).path)
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
        // Name und Symbol des gewählten Themas reisen mit (Neuanlage, falls es beim Übernehmen fehlt)
        let chosen = AIResultRecord(result: StructureResult(title: "T", cleanText: nil, topic: .existing("t_1"), tasks: [], related: []),
                                    chosenTopic: TopicLabel(name: "Boote", icon: .flag))
        try await store.saveAIResult(thought.id, chosen)
        #expect(await store.aiResultRecord(thought.id)?.chosenTopic == TopicLabel(name: "Boote", icon: .flag))
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

    @Test func trashIsPurgedAfterThirtyDays() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let clock = TestClock()
        let store = try ThoughtStore(root: root, now: clock.function)
        let kept = StoreSupport.thought(), trashed = StoreSupport.thought()
        try await store.save(kept)
        try await store.save(trashed)
        try await store.delete(trashed.id)
        #expect(ThoughtStore.trashRetention == 30 * 86_400)

        await store.housekeeping(now: clock.now.addingTimeInterval(29 * 86_400))
        #expect(await store.thought(trashed.id) != nil)

        await store.housekeeping(now: clock.now.addingTimeInterval(31 * 86_400))
        #expect(await store.thought(trashed.id) == nil) // „Zuletzt gelöscht“ nach 30 Tagen weg
        #expect(!FileManager.default.fileExists(atPath: store.directory(trashed.id).path))
        #expect(await store.thought(kept.id) != nil)
    }

    // MARK: Nur Transkripte – Ton nur bis zum Rohtext

    @Test func soundIsDeletedAsSoonAsTheSourceIsSaved() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
        writer.append(StoreSupport.tone(seconds: 1))
        try await store.finishCapture(thought.id, durationMs: writer.close())
        let wav = store.wavURL(thought.id)
        #expect(await store.releaseAudio(thought.id) == false) // ohne Rohtext nie
        #expect(FileManager.default.fileExists(atPath: wav.path))

        try await store.saveSourceOnce(thought.id, ThoughtSource(text: "hallo", sentences: [], model: "whisper-large-v3",
                                                                 createdAt: Date(), languages: ["de"], audioSeconds: 1))
        #expect(!FileManager.default.fileExists(atPath: wav.path))
        #expect(await store.thought(thought.id)?.audio == nil)
        #expect(await store.audioURL(thought.id) == nil)
        #expect(await store.thought(thought.id)?.durationMs == 1_000) // Dauer bleibt als Angabe
        // auf der Platte: nur Text
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory(thought.id).path).sorted()
        #expect(files == ["source.json", "thought.json"])
        let reloaded = try ThoughtStore(root: root)
        #expect(await reloaded.source(thought.id)?.text == "hallo")
        #expect(await reloaded.thought(thought.id)?.audio == nil)
    }

    @Test func runningCaptureKeepsItsSoundUntilFinished() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.5))
        try await store.saveSourceOnce(thought.id, ThoughtSource(text: "live", sentences: [], model: "whisper-large-v3",
                                                                 createdAt: Date(), languages: ["de"], audioSeconds: 0.5))
        #expect(FileManager.default.fileExists(atPath: store.wavURL(thought.id).path)) // Aufnahme läuft noch
        #expect(await store.releaseAudio(thought.id) == false)
        try await store.finishCapture(thought.id, durationMs: writer.close())
        await store.housekeeping(now: Date())
        #expect(await store.thought(thought.id)?.audio == nil)
        #expect(!FileManager.default.fileExists(atPath: store.wavURL(thought.id).path))
    }

    /// Bestandsdaten: Ton aller Gedanken mit Rohtext weg (früher 30 Tage als m4a, abgebrochene Umwandlung,
    /// Papierkorb, Absturz zwischen Löschen und `thought.json`). Ohne Rohtext bleibt die WAV.
    @Test func housekeepingFreesExistingThoughtsFromSound() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let clock = TestClock()
        let encoder = ThoughtJSON.encoder()
        func legacy(_ state: ThoughtState, audio: String, files: [String], source: Bool, deletedAt: Date? = nil) throws -> String {
            var thought = StoreSupport.thought(createdAt: clock.now, state: state)
            thought.audio = Thought.AudioInfo(file: audio)
            thought.deletedAt = deletedAt
            var json = try JSONSerialization.jsonObject(with: encoder.encode(thought)) as! [String: Any]
            json["audio"] = ["file": audio, "deleteAfter": ThoughtJSON.milliseconds(clock.now) + 30 * 86_400_000] // altes Format
            let dir = root.appendingPathComponent("thoughts/\(thought.id)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("thought.json"))
            for name in files { try Data(count: 1_000).write(to: dir.appendingPathComponent(name)) }
            if source {
                let raw = ThoughtSource(text: "alt", sentences: [], model: "whisper-large-v3", createdAt: clock.now, languages: ["de"], audioSeconds: 1)
                try encoder.encode(raw).write(to: dir.appendingPathComponent("source.json"))
            }
            return thought.id
        }
        let compacted = try legacy(.done, audio: "audio.m4a", files: ["audio.m4a"], source: true)
        let halfway = try legacy(.done, audio: "audio.m4a", files: ["audio.wav", "audio.m4a"], source: true)
        let trashed = try legacy(.transcribed, audio: "audio.wav", files: ["audio.wav"], source: true, deletedAt: clock.now)
        let crashed = try legacy(.done, audio: "audio.wav", files: [], source: true)
        let waiting = try legacy(.waitingNetwork, audio: "audio.wav", files: ["audio.wav"], source: false)

        let store = try ThoughtStore(root: root, now: clock.function)
        await store.housekeeping(now: clock.now)
        for id in [compacted, halfway, trashed, crashed] {
            #expect(await store.thought(id)?.audio == nil)
            #expect(!FileManager.default.fileExists(atPath: store.wavURL(id).path))
            #expect(!FileManager.default.fileExists(atPath: store.m4aURL(id).path))
            #expect(await store.source(id)?.text == "alt") // Text bleibt
        }
        #expect(await store.thought(trashed)?.deletedAt != nil) // bleibt im Papierkorb
        #expect(await store.thought(waiting)?.audio?.file == "audio.wav") // nicht verschriftlicht: Ton bleibt
        #expect(FileManager.default.fileExists(atPath: store.wavURL(waiting).path))
        // einmal: ein zweiter Lauf ändert nichts mehr
        let revs = await store.all().map(\.rev).sorted()
        await store.housekeeping(now: clock.now)
        #expect(await store.all().map(\.rev).sorted() == revs)
        // dauerhaft
        let reloaded = try ThoughtStore(root: root)
        #expect(await reloaded.thought(compacted)?.audio == nil)
    }

    // MARK: Themen verschwinden mit ihren Gedanken

    @Test func purgingTheLastThoughtRemovesItsTopic() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        try await store.saveTopics([
            Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .ai),
            Topic(id: "t_beds", title: "Beete", icon: .leaf, owner: .ai, mergedInto: "t_garden"), // Alias
            Topic(id: "t_flat", title: "Wohnung", icon: .home, owner: .user),
            Topic(id: "t_manual", title: "Von Hand", icon: .pencil, owner: .user), // nie ein Gedanke
            Topic(id: "t_books", title: "Lesen", icon: .book, owner: .ai),
        ])
        try await store.setDeclinedMerges([["t_books", "t_garden"], ["t_books", "t_flat"]])
        try await store.setPendingSuggestions([TopicSuggestion(a: "t_garden", b: "t_books", name: nil, reason: "a"),
                                               TopicSuggestion(a: "t_flat", b: "t_books", name: nil, reason: "b")])
        let garden = StoreSupport.thought(topicId: "t_beds") // hängt über den Alias am Garten
        let flat = StoreSupport.thought(topicId: "t_flat")
        let flatTrashed = StoreSupport.thought(topicId: "t_flat")
        let book = StoreSupport.thought(topicId: "t_books")
        for thought in [garden, flat, flatTrashed, book] { try await store.save(thought) }
        try await store.delete(flatTrashed.id)

        await store.purge(garden.id)
        #expect(Set(await store.topics().map(\.id)) == ["t_flat", "t_manual", "t_books"]) // samt Alias
        #expect(await store.topicsInfo().declinedMerges == [["t_books", "t_flat"]])
        #expect(await store.pendingSuggestions().map(\.a) == ["t_flat"])

        await store.purge(flat.id)
        #expect(await store.topics().contains { $0.id == "t_flat" }) // ein Gedanke liegt noch im Papierkorb

        await store.purge([flatTrashed.id])
        #expect(Set(await store.topics().map(\.id)) == ["t_manual", "t_books"]) // auch Nutzer-Themen
        #expect(await store.topicsInfo().declinedMerges.isEmpty)
        #expect(await store.pendingSuggestions().isEmpty)
        let reloaded = try ThoughtStore(root: root)
        #expect(Set(await reloaded.topics().map(\.id)) == ["t_manual", "t_books"])
    }

    /// Ein Thema verschwindet (letzter Gedanke endgültig gelöscht), während ein Lauf es zuweist: Die Zuweisung prüft
    /// im Speicher-Akteur, dass es das Thema gibt, und legt es sonst im selben Schritt wieder an – nie eine ID ins Leere.
    @Test func assigningATopicThatJustVanishedCreatesItAgain() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let boats = Topic(id: "t_boats", title: "Boote", icon: .flag, owner: .ai)
        try await store.saveTopics([boats])
        let last = StoreSupport.thought(topicId: boats.id)
        let fresh = StoreSupport.thought(state: .structuring, topicId: nil)
        let mine = StoreSupport.thought(state: .structuring, topicId: nil)
        let gone = StoreSupport.thought(state: .structuring, topicId: nil)
        for thought in [last, fresh, mine, gone] { try await store.save(thought) }
        await store.purge(last.id)
        #expect(await store.topics().isEmpty) // Thema ging mit seinem letzten Gedanken

        // Gedanke, der es nicht trägt (Nutzer-Thema): nichts wird angelegt
        try await store.update(mine.id) { $0.topicOwner = .user }
        let kept = try await store.update(mine.id, topic: boats) { t, topicID in
            if t.topicOwner != .user { t.topicId = topicID }
        }
        #expect(kept?.topicId == nil)
        #expect(await store.topics().isEmpty)
        // gelöschter Gedanke: nichts wird angelegt
        await store.purge(gone.id)
        let missing = try await store.update(gone.id, topic: boats) { t, topicID in t.topicId = topicID }
        #expect(missing == nil)
        #expect(await store.topics().isEmpty)

        let updated = try await store.update(fresh.id, topic: boats) { t, topicID in
            t.topicId = topicID
            t.topicOwner = .ai
        }
        #expect(updated?.topicId == boats.id)
        #expect(await store.topics() == [boats])
        #expect(await store.resolveTopic(updated?.topicId)?.title == "Boote")
        // vorhandenes Thema (auch über einen Alias): keine Kopie
        try await store.updateTopics { $0.append(Topic(id: "t_alias", title: "Kähne", icon: .flag, owner: .ai, mergedInto: boats.id)) }
        let alias = try await store.update(fresh.id, topic: Topic(id: "t_alias", title: "Kähne", icon: .flag, owner: .ai)) { t, topicID in
            t.topicId = topicID
        }
        #expect(alias?.topicId == boats.id)
        #expect(await store.topics().count == 2)
        let reloaded = try ThoughtStore(root: root)
        #expect(Set(await reloaded.topics().map(\.id)) == [boats.id, "t_alias"])
    }

    /// Prüfer-Fall: Mehrere Läufe haben je ein neues „Boote“ erzeugt (verschiedene IDs, Namensprüfung vor dem Speichern
    /// bestanden) und weisen gleichzeitig zu. Die Namensprüfung im selben Speicher-Schritt nimmt ab dem zweiten das
    /// vorhandene Thema – nie zwei gleichnamige. Ebenso, wenn der Nutzer das Thema in diesem Fenster anlegt.
    @Test func parallelRunsNeverCreateTheSameTopicTwice() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let thoughts = (0..<8).map { _ in StoreSupport.thought(state: .structuring, topicId: nil) }
        for thought in thoughts { try await store.save(thought) }
        let proposals = thoughts.indices.map { i in
            Topic(title: ["Boote", "boote", "Boote", "BOOTE"][i % 4], icon: .flag, owner: .ai)
        }
        #expect(Set(proposals.map(\.id)).count == proposals.count)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (thought, topic) in zip(thoughts, proposals) {
                group.addTask {
                    _ = try await store.update(thought.id, topic: topic) { t, topicID in
                        t.topicId = topicID
                        t.topicOwner = .ai
                    }
                }
            }
            try await group.waitForAll()
        }
        let topics = await store.topics()
        #expect(topics.count == 1)
        let boats = try #require(topics.first)
        #expect(proposals.map(\.id).contains(boats.id))
        for thought in thoughts { #expect(await store.thought(thought.id)?.topicId == boats.id) }
        let reloaded = try ThoughtStore(root: root)
        #expect(await reloaded.topics().map { [$0.id, $0.title] } == [[boats.id, boats.title]]) // so auch auf der Platte

        // Der Nutzer legt „Segeln“ an, nachdem ein Lauf es als neu erkannt hat: der Lauf nimmt das des Nutzers
        let late = Topic(title: "Segeln", icon: .flag, owner: .ai)
        let own = Topic(title: "Segeln", icon: .heart, owner: .user)
        try await store.updateTopics { $0.append(own) }
        let assigned = try await store.update(thoughts[0].id, topic: late) { t, topicID in t.topicId = topicID }
        #expect(assigned?.topicId == own.id)
        #expect(await store.topics() == [boats, own])

        // Mehrdeutig (zwei gleich gute Titel): ohne Thema, kein drittes gleichnamiges
        let apps = [Topic(title: "Paply App", icon: .code, owner: .user), Topic(title: "Paply-App", icon: .code, owner: .user)]
        try await store.updateTopics { $0.append(contentsOf: apps) }
        let ambiguous = try await store.update(thoughts[1].id, topic: Topic(title: "paply app", icon: .code, owner: .ai)) { t, topicID in
            t.topicId = topicID
        }
        #expect(ambiguous?.topicId == nil)
        #expect(await store.topics() == [boats, own] + apps)
    }

    @Test func purgeAllAndThirtyDayPurgeTakeTheirTopicsAlong() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let clock = TestClock()
        let store = try ThoughtStore(root: root, now: clock.function)
        try await store.saveTopics([Topic(id: "t_a", title: "Umzug", icon: .home, owner: .ai),
                                    Topic(id: "t_b", title: "Laufen", icon: .heart, owner: .user),
                                    Topic(id: "t_c", title: "Porto", icon: .plane, owner: .ai),
                                    Topic(id: "t_manual", title: "Von Hand", icon: .pencil, owner: .user)])
        let thoughts = [StoreSupport.thought(topicId: "t_a"), StoreSupport.thought(topicId: "t_a"),
                        StoreSupport.thought(topicId: "t_b"), StoreSupport.thought(topicId: "t_c")]
        for thought in thoughts {
            try await store.save(thought)
            try await store.delete(thought.id)
        }
        await store.purge(thoughts.prefix(2).map(\.id)) // „Alle löschen“ (Teil)
        #expect(Set(await store.topics().map(\.id)) == ["t_b", "t_c", "t_manual"])
        await store.housekeeping(now: clock.now.addingTimeInterval(31 * 86_400)) // Rest nach 30 Tagen
        #expect(await store.all().isEmpty)
        #expect(await store.topics().map(\.id) == ["t_manual"])
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
