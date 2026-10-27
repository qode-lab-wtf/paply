import Foundation

/// Diagnose-Ereignisse der Gedanken-Verarbeitung (Umschrift, Ordnung, Groq-Aufrufe, Wartegründe).
///
/// Die App leitet sie ins Diagnoseprotokoll (`Diag.log`, `ThoughtsEnvironment`). Erlaubt sind nur Kurz-IDs,
/// Zahlen (Längen, Dauer in ms, Tokens), Modellnamen und feste Codes – **nie** Text, Titel, Themennamen,
/// Aufgaben oder Zitate (Tests `ThoughtTraceTests`).
///
/// | Ereignis | Felder |
/// | --- | --- |
/// | `thought.transcribe.begin` | `id`, `model`, `audioS` |
/// | `thought.transcribe.end` | `id`, `result` (ok, noSpeech, Fehlercode), `ms`, `textLen`, `langs`, `audioS`, `live` |
/// | `thought.structure.begin` | `id`, `textLen`, `parts`, `topics`, `candidates` |
/// | `thought.structure.cached` | `id` (Ergebnis lag schon als `ai-result.json`, kein Aufruf) |
/// | `thought.groq` | `id`, `model`, `effort`, `part`, `status` (ok, http-429 …), `groqCode`, `finish`, `ms`, `tokens`, `promptTokens`, `completionTokens`, `estimate`, `retryAfterS`, `valid`, `codes`, `next` |
/// | `thought.groq.ledger` | `id`, `model`, `reason` (minute, budget, tooSmall), `waitS` |
/// | `thought.structure.end` | `id`, `ms`, `result` (ok, wait, raw, cancelled), `code`, `model`, `fallback`, `tokens`, `tasks`, `topic` (existing, new, none), `links`, `textIsRaw`, `rejections` |
/// | `thought.wait` | `id`, `state`, `waitS`, `attempts` |
/// | `thought.wait.dictation` | `id`, `ms` |
/// | `thought.attention` | `id`, `why`, `attempts` |
/// | `thought.empty` | `id` |
public struct ThoughtTrace: Sendable {
    public enum Value: Sendable, Equatable {
        case s(String)
        case i(Int)
        case d(Double)
        case b(Bool)

        /// Millisekunden bzw. Sekunden auf eine Nachkommastelle
        static func ms(_ value: Double) -> Value { .d((value * 10).rounded() / 10) }
    }

    public typealias Fields = [String: Value]

    private let sink: (@Sendable (String, Fields) -> Void)?

    public init(_ sink: @escaping @Sendable (String, Fields) -> Void) {
        self.sink = sink
    }

    private init() {
        sink = nil
    }

    /// Kein Protokoll (Tests, Prüfstand).
    public static let off = ThoughtTrace()

    func log(_ event: String, _ fields: Fields) {
        sink?(event, fields)
    }

    /// Kurz-ID des Gedankens, dem die Groq-Aufrufe gerade gehören. Setzt der Prozessor um jeden Aufruf des
    /// Strukturierers; dieser schreibt sie in `thought.groq`.
    @TaskLocal static var thoughtID: String?

    /// Gleiche Kürzung wie `ThoughtCapture.short` in der App.
    static func short(_ id: String) -> String { String(id.prefix(10)) }

    static func milliseconds(since start: ContinuousClock.Instant) -> Value {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return .ms(ms)
    }
}
