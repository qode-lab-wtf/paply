import Foundation

// Datenformate, die App, Tastatur und Widgets über die App Group austauschen.
// Diktat-Texte stehen nur in `results/` (bis die Tastatur sie abholt) und in
// `pending-text.json` (Schnelltaste) – nie im Diagnoseprotokoll.

/// Zustand des Mikros in der App.
enum SessionStatus: String, Codable, Sendable {
    /// keine Sitzung
    case off
    /// Mikro bereit, Leerlauf (nur Vorlauf-Puffer im Speicher)
    case ready
    /// ein Diktat nimmt gerade auf
    case recording
    /// Unterbrechung und Wiederanlauf fehlgeschlagen
    case interrupted
}

enum DictationSource: String, Codable, Sendable {
    case keyboard
    case shortcut
}

enum DictationPhase: String, Codable, Sendable {
    case recording
    case processing
    case done
    case cancelled
    case failed
}

enum DictationErrorCode: String, Codable, Sendable {
    case noAPIKey
    case sessionNotReady
    case interrupted
}

struct DictationStatus: Codable, Sendable, Equatable {
    var id: String
    var source: DictationSource
    var phase: DictationPhase
    /// MonoClock beim Aufnahmestart in der App
    var startedNs: UInt64
    var speechDetected: Bool
    var errorCode: DictationErrorCode?
}

/// `session.json` – von der App geschrieben, von Tastatur und Widgets gelesen.
struct SessionState: Codable, Sendable, Equatable {
    var status: SessionStatus = .off
    var sessionID: String?
    var startedAt: Date?
    var lastActivityAt: Date?
    /// nil = bis Neustart
    var holdUntil: Date?
    var pid: Int32 = 0
    /// MonoClock beim letzten Schreiben
    var updatedNs: UInt64 = 0
    /// MonoClock der letzten Antwort auf `ping`
    var pongNs: UInt64 = 0
    var hasAPIKey: Bool = false
    /// z. B. Unterbrechungsgrund
    var detail: String?
    var dictation: DictationStatus?
}

/// `keyboard-command.json` – letzter Wunsch der Tastatur. Darwin-Notifications
/// können zusammenfallen; die App gleicht deshalb immer mit dem letzten Stand ab.
struct KeyboardCommand: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        case record
        case finish
        /// Tastatur verschwindet nach erkannter Sprache: fertig machen, aber nicht einsetzen –
        /// das Ergebnis kommt in den Verlauf und wird beim nächsten 🌐 einmal angeboten.
        case finishLater
        /// Nach endgültigem Fehler dasselbe Audio erneut senden
        case retry
        case cancel
    }

    var dictationID: String
    var action: Action
    var sentNs: UInt64
}

/// Zeiten eines Diktats (Spiegel von PaplyKit.DictationTimings plus App-Anteile).
struct ResultTimings: Codable, Sendable, Equatable {
    var transcriptionDoneMs: Double?
    var polishDoneMs: Double?
    var totalMs: Double?
    var chunkCount: Int = 0
    var uploadedBytes: Int = 0
    var audioSeconds: Double = 0
    /// Warten auf die letzten Audio-Blöcke nach „fertig“
    var flushMs: Double?
    /// Befehl gesendet (Tastatur) → in der App angekommen
    var commandLatencyMs: Double?
    /// Für die Auswertung je Kombination
    var model: String?
    var chunked: Bool?
    /// wifi / cellular / wired / other / none
    var net: String?
    /// Testvarianten der Pipeline, z. B. „flac·primer·polish“ (Standard)
    var options: String?
}

/// `results/<id>.json` – Ergebnis für die Tastatur. Wird nach dem Einsetzen gelöscht.
struct DictationResult: Codable, Sendable {
    var dictationID: String
    /// "" = nichts einsetzen
    var text: String
    var errorMessage: String?
    var timings: ResultTimings
    /// Polieren scheiterte technisch – Rohtext eingesetzt (nur für ein dezentes Zeichen)
    var unpolished: Bool?
    /// Fehler lässt sich mit demselben Audio erneut senden
    var retryable: Bool?
    /// Keine Sprache erkannt (Stille, Rauschen) – nichts einsetzen, „Nichts verstanden“ zeigen
    var noSpeech: Bool?
    /// MonoClock: Befehl „finish“ in der App angekommen
    var finishReceivedNs: UInt64
    /// MonoClock: Ergebnis geschrieben
    var writtenNs: UInt64
}

/// `pending-text.json` – wartender Text (Schnelltaste, oder Tastatur verschwand nach Sprache).
/// Die Tastatur bietet ihn genau einmal an („Einsetzen“) und löscht ihn dabei.
struct PendingText: Codable, Sendable {
    var id: String
    var text: String
    var createdAt: Date

    static let lifetime: TimeInterval = 10 * 60
    var isFresh: Bool { Date().timeIntervalSince(createdAt) < Self.lifetime }
}

/// `shortcut-command.json` – Schnelltaste aus dem Widget-Prozess.
struct ShortcutCommand: Codable, Sendable {
    var seq: UInt64
    var sentNs: UInt64
}

/// `shortcut-ack.json` – Antwort der App auf eine Schnelltaste.
struct ShortcutAck: Codable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case started
        case stopped
        case failed
    }

    var seq: UInt64
    var outcome: Outcome
    var detail: String?
    var ackNs: UInt64
}

/// `thought-state.json` – nur ob gerade ein Gedanke aufnimmt (für Control und Widget). Kein Text.
struct ThoughtStateFile: Codable, Sendable, Equatable {
    var recording: Bool
    var id: String?
    var startedAt: Date?
}

/// `keyboard-report.json` – die Tastatur meldet ihre eigene Höhe (für die Höhenmessung).
struct KeyboardReport: Codable, Sendable {
    var viewHeight: Double
    var landscape: Bool
    var ns: UInt64
}
