import Foundation

public actor VoiceProfileStore {
    public nonisolated let root: URL
    private var processing = false
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
        var all = try people()
        if let i = all.firstIndex(where: { $0.id == id }) { all[i].prints = []; all[i].updatedAt = Date() }
        try save(all)
        if id == VoicePerson.ownerID, FileSafety.exists(learningDirectory) { try FileManager.default.removeItem(at: learningDirectory) }
    }
    public func add(_ print: VoicePrint, to id: String) throws {
        guard !print.vector.isEmpty, print.vector.allSatisfy(\.isFinite), print.seconds.isFinite, print.seconds > 0 else { return }
        var all = try people()
        guard let i = all.firstIndex(where: { $0.id == id }) else { throw ThoughtStoreError.notFound }
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
                let owner = try people().first { $0.isOwner }!
                let same = owner.prints.filter { $0.model == print.model }
                if same.isEmpty || SpeakerThresholds.score(print, against: owner) >= SpeakerThresholds.learning {
                    print.source = .thought
                    try add(print, to: VoicePerson.ownerID)
                }
            }
            try FileManager.default.removeItem(at: file)
        }
    }
}
