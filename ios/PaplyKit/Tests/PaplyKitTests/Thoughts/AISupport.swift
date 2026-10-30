import Foundation
import Synchronization
@testable import PaplyKit

/// Gemeinsame Bausteine der KI-Tests (H1).
enum AIFixture {
    static let topics = [
        TopicIndexEntry(topicID: "t_paply", name: "Paply", count: 14, hint: ["Tastatur", "Groq", "Sperrbildschirm"]),
        TopicIndexEntry(topicID: "t_umzug", name: "Umzug", count: 9, hint: ["Wohnung", "Makler", "Kreuzberg"]),
        TopicIndexEntry(topicID: "t_wohnung", name: "Wohnung", count: 3, hint: ["Miete"]),
        TopicIndexEntry(topicID: "t_lissabon", name: "Lissabon", count: 2, hint: ["Reise"]),
        TopicIndexEntry(topicID: "t_garten", name: "Garten", count: 1, hint: ["Tomaten", "Beet"]),
    ]

    static let candidates = [
        CandidateEntry(thoughtID: "s_oranien", title: "Wohnung Oranienstraße besichtigen", topicID: "t_umzug",
                       when: "vor 2 Tagen", excerpt: "Die Wohnung in der Oranienstraße hat zwei Zimmer und einen Balkon …",
                       localScore: 0.82),
        CandidateEntry(thoughtID: "s_tomaten", title: "Tomaten umtopfen", topicID: "t_garten", when: "gestern",
                       excerpt: "Die Tomaten brauchen größere Töpfe, am Wochenende umtopfen.", localScore: 0.41),
        CandidateEntry(thoughtID: "s_sperr", title: "Sperrbildschirm-Knopf", topicID: "t_paply", when: "heute 08:10",
                       excerpt: "Der Knopf im Sperrbildschirm soll statt der Taschenlampe …", localScore: 0.9),
        CandidateEntry(thoughtID: "s_alt", title: "Alte Notiz", topicID: nil, when: "12. Sep.", excerpt: "Irgendwas.",
                       localScore: 0.36),
    ]

    static let transcript = "Ähm, also zur Wohnung in der Oranienstraße, ich hab jetzt nochmal mit dem Makler telefoniert. Die Miete ist 1.450 Euro warm und nicht verhandelbar. Ich muss bis Freitag die Unterlagen schicken. Und nicht vergessen, die Schufa-Auskunft zu bestellen."

    static func input(transcript: String = transcript, topics: [TopicIndexEntry] = topics,
                      candidates: [CandidateEntry] = candidates, topicsFull: Bool = false, vocabulary: String = "",
                      part: (index: Int, count: Int)? = nil, effort: String = "low") -> StructureInput {
        StructureInput(transcript: transcript, sentences: [], spokenLanguages: ["de"], uiLanguage: "de",
                       vocabulary: vocabulary, topics: topics, topicsFull: topicsFull, candidates: candidates,
                       part: part, reasoningEffort: effort)
    }

    static let goodClean = "Zur Wohnung in der Oranienstraße: Ich habe jetzt nochmal mit dem Makler telefoniert. Die Miete ist 1.450 Euro warm und nicht verhandelbar.\n\nIch muss bis Freitag die Unterlagen schicken. Und nicht vergessen, die Schufa-Auskunft zu bestellen."

    static func topic(_ choice: String, id: String? = nil, name: String? = nil, symbol: String = "home") -> [String: Any] {
        ["choice": choice, "id": id as Any? ?? NSNull(), "new_name": name as Any? ?? NSNull(), "symbol": symbol]
    }

    static func task(_ text: String, _ quote: String, due: String? = nil) -> [String: Any] {
        ["text": text, "quote": quote, "due_hint": due as Any? ?? NSNull()]
    }

    static func link(_ ref: String, _ kind: String = "continues", _ reason: String = "Gleiche Wohnung", _ confidence: String = "high") -> [String: Any] {
        ["ref": ref, "kind": kind, "reason": reason, "confidence": confidence]
    }

    static func answer(title: String = "Wohnung Oranienstraße Unterlagen", clean: String = goodClean,
                       topic: [String: Any] = topic("existing", id: "t2"), tasks: [[String: Any]] = [],
                       related: [[String: Any]] = []) -> String {
        let object: [String: Any] = ["title": title, "clean_text": clean, "topic": topic, "tasks": tasks, "related": related]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// Prüft eine Antwort gegen eine Eingabe (Aliasse wie beim echten Senden).
    static func validate(_ json: String, _ input: StructureInput = input(), selfID: String? = nil) -> StructureResult {
        let aliases = try! ThoughtPrompt.build(input).aliases
        guard case .success(let result) = ThoughtValidator.validate(json: json, input: input, aliases: aliases, selfID: selfID) else {
            fatalError("Validierung unerwartet gescheitert")
        }
        return result
    }

    /// Groq-Antwort mit strukturiertem Inhalt (ohne Stream).
    static func reply(_ content: String, finish: String = "stop", total: Int = 3_400) -> MockServer.Reply {
        .json(200, ["choices": [["index": 0, "finish_reason": finish, "message": ["role": "assistant", "content": content]]],
                    "usage": ["prompt_tokens": total - 900, "completion_tokens": 900, "total_tokens": total]])
    }
}

/// Fängt Diagnose-Ereignisse (`ThoughtTrace`) für Tests.
final class TraceRecorder: Sendable {
    private let state = Mutex<[(name: String, fields: ThoughtTrace.Fields)]>([])

    var trace: ThoughtTrace {
        ThoughtTrace { [self] name, fields in self.state.withLock { $0.append((name, fields)) } }
    }

    var events: [(name: String, fields: ThoughtTrace.Fields)] { state.withLock { $0 } }

    func named(_ name: String) -> [ThoughtTrace.Fields] { events.filter { $0.name == name }.map(\.fields) }

    /// Alle Text-Werte aller Ereignisse
    var strings: [String] {
        events.flatMap { $0.fields.values.compactMap { value -> String? in
            if case .s(let text) = value { return text }
            return nil
        } }
    }
}
