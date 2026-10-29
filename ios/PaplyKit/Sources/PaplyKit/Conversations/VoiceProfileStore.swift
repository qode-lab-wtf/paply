import Foundation

public actor VoiceProfileStore {
    public nonisolated let root: URL
    private var processing = false
    private var generation = 0
    public init(root: URL) { self.root = root }
    private var file: URL { root.appendingPathComponent("voices.json") }

    public func people() throws -> [VoicePerson] {
        guard FileSafety.exists(file) else { return [VoicePerson(id: VoicePerson.ownerID, name: "")] }
        var all = try ThoughtJSON.decoder().decode([VoicePerson].self, from: Data(contentsOf: file))
        if !all.contains(where: { $0.isOwner }) { all.insert(VoicePerson(id: VoicePerson.ownerID, name: ""), at: 0) }
        return all
    }
    private func save(_ people: [VoicePerson]) throws {
        try FileSafety.createDirectory(root)
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(people), to: file)
    }
    @discardableResult public func create(name: String) throws -> VoicePerson {
        var all = try people()
        let person = VoicePerson(id: UUID().uuidString, name: name)
        all.append(person)
        try save(all)
        return person
    }
    public func rename(_ id: String, name: String) throws {
        var all = try people()
        guard let i = all.firstIndex(where: { $0.id == id }), id != VoicePerson.ownerID else { return }
        all[i].name = name; all[i].updatedAt = Date()
        try save(all)
    }
    public func delete(_ id: String) throws {
        if id == VoicePerson.ownerID { try forgetVoice(id); return }
        try save(people().filter { $0.id != id })
    }
    public func forgetVoice(_ id: String) throws {
        if id == VoicePerson.ownerID { generation += 1 }
        var all = try people()
        if let i = all.firstIndex(where: { $0.id == id }) { all[i].prints = []; all[i].updatedAt = Date() }
        try save(all)
        if id == VoicePerson.ownerID, FileSafety.exists(countFile) { try FileManager.default.removeItem(at: countFile) }
        if id == VoicePerson.ownerID, FileSafety.exists(candidatesFile) { try FileManager.default.removeItem(at: candidatesFile) }
        if id == VoicePerson.ownerID, FileSafety.exists(learningDirectory) { try FileManager.default.removeItem(at: learningDirectory) }
    }
    public func add(_ print: VoicePrint, to id: String) throws {
        guard !print.vector.isEmpty, print.vector.allSatisfy(\.isFinite), print.seconds.isFinite, print.seconds > 0 else { return }
        var all = try people()
        guard let i = all.firstIndex(where: { $0.id == id }) else { throw ThoughtStoreError.notFound }
        let learned = id == VoicePerson.ownerID && print.source == .thought ? try learnedCount(all[i]) + 1 : nil
        all[i].prints.append(print)
        // Das ähnlichste Paar ausdünnen: älteren Abdruck entfernen, verschiedene Lagen behalten.
        while all[i].prints.count > 20 {
            let prints = all[i].prints
            var victim = 0, closest = -Double.infinity
            for a in prints.indices { for b in prints.indices where b > a && prints[a].model == prints[b].model {
                let score = SpeakerThresholds.cosine(prints[a].vector, prints[b].vector)
                if score > closest { closest = score; victim = prints[a].createdAt < prints[b].createdAt ? a : b }
            } }
            all[i].prints.remove(at: victim)
        }
        all[i].updatedAt = Date()
        try save(all)
        if let learned {
            try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(learned), to: countFile)
        }
    }
    public nonisolated var learningDirectory: URL { root.appendingPathComponent("voice-learning") }
    /// Synchroner Haken: Kopie ist dauerhaft, bevor ThoughtStore den Ton entfernt.
    public nonisolated func learningHook() -> @Sendable (URL) -> Void {
        let directory = learningDirectory
        return { source in
            do {
                try FileSafety.createDirectory(directory)
                let target = directory.appendingPathComponent(UUID().uuidString + ".wav")
                try FileManager.default.copyItem(at: source, to: target)
                FileSafety.applyProtection(target); FileSafety.excludeFromBackup(target)
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
                    .filter { $0.pathExtension == "wav" }.sorted {
                        ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) <
                        ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    }
                for url in files.prefix(max(0, files.count - 10)) { try FileManager.default.removeItem(at: url) }
            } catch { /* Lernen darf Gedanken nicht aufhalten. */ }
        }
    }
    private var countFile: URL { root.appendingPathComponent("voice-learning-count.json") }
    private func learnedCount(_ owner: VoicePerson) throws -> Int {
        guard FileSafety.exists(countFile) else { return owner.prints.filter { $0.source == .thought }.count }
        return try ThoughtJSON.decoder().decode(Int.self, from: Data(contentsOf: countFile))
    }

    private var candidatesFile: URL { root.appendingPathComponent("voice-candidates.json") }

    private struct LearningCandidate: Codable {
        var id: String
        var print: VoicePrint
    }

    private func candidates() throws -> [LearningCandidate] {
        guard FileSafety.exists(candidatesFile) else { return [] }
        return try ThoughtJSON.decoder().decode([LearningCandidate].self, from: Data(contentsOf: candidatesFile))
    }

    public struct LearningStatus: Sendable, Equatable {
        public var learnedThoughts: Int
        public var isLearning: Bool
    }

    public func learningStatus() throws -> LearningStatus {
        let owner = try people().first { $0.isOwner }!
        return LearningStatus(learnedThoughts: try learnedCount(owner),
                              isLearning: owner.prints.isEmpty)
    }

    /// Bewusstes Einsprechen braucht keine Bestätigung durch weitere Gedanken.
    public func enroll(audio: URL, diarizer: any SpeakerDiarizing) async throws {
        let started = generation
        guard var print = try await diarizer.voiceprint(audio: audio) else { throw ThoughtStoreError.unavailable }
        guard started == generation else { return }
        print.source = .enrollment
        try add(print, to: VoicePerson.ownerID)
    }

    func learn(_ print: VoicePrint, candidateID: String = UUID().uuidString) throws {
        let owner = try people().first { $0.isOwner }!
        if !owner.prints.isEmpty {
            if SpeakerThresholds.score(print, against: owner) >= SpeakerThresholds.learning {
                try add(print, to: VoicePerson.ownerID)
            }
            return
        }
        var records = try candidates()
        guard !records.contains(where: { $0.id == candidateID }) else { return }
        records.append(LearningCandidate(id: candidateID, print: print))
        records = Array(records.suffix(20))
        let pending = records.map(\.print)
        // Größte Clique: jedes Paar muss passen, keine transitive Ähnlichkeitskette.
        var best: [Int] = []
        func search(_ chosen: [Int], _ remaining: [Int]) {
            if chosen.count + remaining.count <= best.count { return }
            if chosen.count > best.count { best = chosen }
            for (offset, index) in remaining.enumerated() {
                let compatible = remaining.dropFirst(offset + 1).filter {
                    pending[index].model == pending[$0].model &&
                    SpeakerThresholds.cosine(pending[index].vector, pending[$0].vector) >= SpeakerThresholds.learning
                }
                search(chosen + [index], compatible)
            }
        }
        search([], Array(pending.indices))
        try FileSafety.createDirectory(root)
        if best.count >= 3 {
            for index in best { try add(pending[index], to: VoicePerson.ownerID) }
            records = []
        }
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(records), to: candidatesFile)
    }

    public func processLearningQueue(diarizer: any SpeakerDiarizing) async throws {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        guard FileSafety.exists(learningDirectory) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: learningDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "wav" }.sorted { $0.path < $1.path }
        for file in files {
            try Task.checkCancellation()
            if var print = try await diarizer.voiceprint(audio: file), print.seconds >= SpeakerThresholds.minimumLearningSeconds {
                // Nach „Vergessen“ während der Diarisierung nicht erneut lernen.
                guard FileSafety.exists(file) else { continue }
                print.source = .thought
                try learn(print, candidateID: file.lastPathComponent)
            }
            try FileManager.default.removeItem(at: file)
        }
    }
}
