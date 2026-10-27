import Foundation
import Synchronization
@testable import PaplyKit

/// Gemeinsame Bausteine der Speicher-, Local- und Prozessor-Tests (H2).
enum StoreSupport {
    /// Eigener leerer Ordner je Test.
    static func temporaryRoot(_ name: String = #function) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paply-h2-tests", isDirectory: true)
            .appendingPathComponent("\(name.prefix(40))-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func thought(id: String = ThoughtIDs.thought(), createdAt: Date = Date(), state: ThoughtState = .done,
                        title: String? = "Titel", text: String? = "Text", topicId: String? = nil,
                        languages: [String] = ["de"]) -> Thought {
        Thought(id: id, createdAt: createdAt, durationMs: 4_000, trigger: .control, state: state, title: title,
                titleOwner: title == nil ? .system : .ai, text: text, textOwner: text == nil ? .system : .ai,
                topicId: topicId, topicOwner: topicId == nil ? .system : .ai, languages: languages, updatedAt: createdAt)
    }

    /// 16-kHz-Samples einer Sinus-„Stimme“.
    static func tone(seconds: Double, frequency: Double = 220) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(0.3 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
    }

    // MARK: Bewertungssatz (Tests/Fixtures/Thoughts)

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Thoughts")
    }

    struct EvalCase {
        var id: String
        var recordedAt: Date
        var transcript: String
        var languages: [String]
        var required: [[String]]
    }

    /// `store-a.json` (ohne abgeleitete Felder) + `eval.jsonl`
    static func storeA() throws -> (thoughts: [Thought], topics: [Topic], cases: [EvalCase]) {
        let store = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("store-a.json"))) as! [String: Any]
        let decoder = ThoughtJSON.decoder()
        let thoughts = try (store["thoughts"] as! [[String: Any]]).map { raw -> Thought in
            var item = raw
            item["keywords"] = item["keywords"] ?? []
            item["status"] = item["status"] ?? ["attempts": 0]
            return try decoder.decode(Thought.self, from: JSONSerialization.data(withJSONObject: item))
        }
        let topics = try ((store["topics"] as! [String: Any])["topics"] as! [[String: Any]]).map {
            try decoder.decode(Topic.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        var cases: [EvalCase] = []
        for line in try String(contentsOf: fixtures.appendingPathComponent("eval.jsonl"), encoding: .utf8).split(separator: "\n") {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let expect = object["expect"] as! [String: Any]
            let related = (expect["related"] as? [[String: Any]] ?? []).filter { ($0["status"] as? String) == "required" }
            cases.append(EvalCase(id: object["id"] as! String,
                                  recordedAt: Date(timeIntervalSince1970: (object["recordedAt"] as! Double) / 1000),
                                  transcript: object["transcript"] as! String,
                                  languages: (object["meta"] as! [String: Any])["spokenLanguages"] as? [String] ?? [],
                                  required: related.map { $0["ids"] as? [String] ?? [] }))
        }
        return (thoughts, topics, cases)
    }
}

/// Verstellbare Uhr für Fristen und Wiederholungen.
final class TestClock: Sendable {
    private let value: Mutex<Date>
    init(_ date: Date = Date(timeIntervalSince1970: 1_793_093_400)) { value = Mutex(date) }
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    func set(_ date: Date) { value.withLock { $0 = date } }
    var function: @Sendable () -> Date { { [self] in now } }
}
