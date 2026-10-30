import Foundation

/// Eigener Ledger, Port von `electron-menubar/notes/ledger.js` (KONZEPT §6.2).
///
/// - Gleitende 24 h je Einheit: Tokens (`dailyTokens`) bzw. Audiosekunden (`dailyAudioSeconds`).
/// - Je Modell und Minute: höchstens `minuteTokens` (Audio: 1 800 s) und `minuteRequests` Anfragen.
/// - Erst reservieren (Schätzung), dann mit dem tatsächlichen Verbrauch abrechnen. Wer nicht
///   abrechnet (Abbruch, Netzfehler), behält die Schätzung – lieber zu vorsichtig.
/// - Gespeichert als `ledger.json` (Array wie am Mac, Zeit in ms), atomar geschrieben. Eine
///   unlesbare Datei beginnt leer (Mac: kein Array → []).
public actor TokenLedger {
    public struct Limits: Sendable {
        public var dailyTokens = 80_000
        public var dailyAudioSeconds = 7_200
        public var minuteTokens = 7_600
        public var minuteRequests = 15
        public init() {}
    }

    public enum Unit: String, Codable, Sendable { case tokens, audio }

    public struct Reservation: Sendable, Hashable {
        public let id: String
        public init(id: String) { self.id = id }
    }

    public enum Refusal: Error, Sendable, Equatable {
        /// Tagesbudget erreicht; frei, sobald die älteste Buchung 24 h alt ist (mindestens 60 s).
        case budget(retryAt: Date)
        /// Die Anfrage allein ist größer als das Tagesbudget (Mac `budget_small`).
        case budgetTooSmall
        /// Minutenfenster des Modells voll (61 s warten).
        case minute(retryAt: Date)
    }

    struct Record: Codable, Equatable {
        var id: String
        /// ms seit 1970
        var at: Double
        var model: String
        var amount: Int
        var unit: Unit
        var pending: Bool
    }

    static let window: TimeInterval = 24 * 60 * 60
    static let minuteAudioSeconds = 1_800

    private let fileURL: URL
    private let limits: @Sendable () -> Limits
    private let now: @Sendable () -> Date
    private var records: [Record]

    public init(fileURL: URL, limits: @escaping @Sendable () -> Limits, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.limits = limits
        self.now = now
        if let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([Record].self, from: data) {
            records = list
        } else {
            records = []
        }
    }

    private var nowMs: Double { now().timeIntervalSince1970 * 1000 }

    private func clean() {
        let cutoff = nowMs - Self.window * 1000
        records.removeAll { $0.at <= cutoff }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func reserve(model: String, amount: Int, unit: Unit) throws(Refusal) -> Reservation {
        clean()
        let limits = limits()
        let amount = max(0, amount)
        let limit = unit == .tokens ? limits.dailyTokens : limits.dailyAudioSeconds
        let minuteLimit = unit == .tokens ? limits.minuteTokens : Self.minuteAudioSeconds
        if amount > limit { throw .budgetTooSmall }

        let sameUnit = records.filter { $0.unit == unit }
        let daily = sameUnit.reduce(0) { $0 + $1.amount }
        let minuteStart = nowMs - 60_000
        let minute = records.filter { $0.model == model && $0.at > minuteStart }
        if daily + amount > limit {
            let oldest = sameUnit.map(\.at).min() ?? nowMs
            let waitMs = max(60_000, oldest + Self.window * 1000 - nowMs)
            throw .budget(retryAt: Date(timeIntervalSince1970: (nowMs + waitMs) / 1000))
        }
        if minute.reduce(0, { $0 + $1.amount }) + amount > minuteLimit || minute.count >= limits.minuteRequests {
            throw .minute(retryAt: Date(timeIntervalSince1970: (nowMs + 61_000) / 1000))
        }
        let record = Record(id: "q_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                            at: nowMs, model: model, amount: amount, unit: unit, pending: true)
        records.append(record)
        save()
        return Reservation(id: record.id)
    }

    /// Abrechnen: `actual` ersetzt die Schätzung (0 bei 401/403/404/429). `nil` behält die Schätzung.
    public func settle(_ reservation: Reservation, actual: Int?) {
        guard let index = records.firstIndex(where: { $0.id == reservation.id }) else { return }
        if let actual, actual >= 0 { records[index].amount = actual }
        records[index].pending = false
        save()
    }

    public func summary() -> (tokens: Int, audioSeconds: Int, requests: Int) {
        clean()
        return (records.filter { $0.unit == .tokens }.reduce(0) { $0 + $1.amount },
                records.filter { $0.unit == .audio }.reduce(0) { $0 + $1.amount },
                records.count)
    }

    /// Verbrauch eines Modells in den letzten 24 h (für Prüfstand und Anzeige).
    public func used(model: String) -> Int {
        clean()
        return records.filter { $0.model == model && $0.unit == .tokens }.reduce(0) { $0 + $1.amount }
    }
}
