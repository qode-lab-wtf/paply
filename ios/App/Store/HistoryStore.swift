import Foundation
import Observation
import PaplyKit

struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var date: Date
    var source: DictationSource
    var text: String
    var raw: String
    var polished: String?
    var polishRejection: String?
    var errorMessage: String?
    var languages: [String]
    var timings: ResultTimings
    /// Technischer Grund, warum nicht poliert wurde (z. B. „http-429“) – dann ist `text` der Rohtext
    var polishError: String?
    /// Tatsächlich verwendetes Polier-Modell
    var polishModel: String?
    /// Wie oft erneut gesendet wurde
    var retries: Int?
}

/// Verlauf nur im App-Container (nicht in der App Group – die Tastatur braucht ihn nicht).
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    private static let limit = 300

    private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = stored
        }
    }

    /// Neuer Eintrag – oder Ersatz des Eintrags mit derselben ID (nach „Erneut versuchen“).
    func add(id: String, source: DictationSource, outcome: DictationOutcome, timings: ResultTimings, retries: Int = 0) {
        let entry = HistoryEntry(
            id: id,
            date: Date(),
            source: source,
            text: outcome.text,
            raw: outcome.raw,
            polished: outcome.polished,
            polishRejection: outcome.polishRejection,
            errorMessage: outcome.errorMessage,
            languages: outcome.languages,
            timings: timings,
            polishError: outcome.polishError,
            polishModel: outcome.polishModel,
            retries: retries > 0 ? retries : nil
        )
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func delete(_ ids: Set<String>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        save()
    }

    /// Bis zu 3 Rohdiktate der letzten 30 Minuten (Kontext fürs Polieren), ältestes zuerst –
    /// so erwartet es PaplyKit. `entries` ist neuestes zuerst, daher die 3 neuesten umdrehen.
    /// Im Verlauf stehen nur Tastatur- und Schnelltasten-Diktate.
    func recentRawDictations(now: Date = Date()) -> [String] {
        entries
            .filter { now.timeIntervalSince($0.date) < 30 * 60 && !$0.raw.isEmpty }
            .prefix(3)
            .reversed()
            .map(\.raw)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
