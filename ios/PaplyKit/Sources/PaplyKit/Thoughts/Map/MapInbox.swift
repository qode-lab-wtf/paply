import CoreGraphics
import Foundation

// „Eingang“ der Karte: Gedanken, die Paply gerade ordnet oder die warten, stehen noch auf keinem Kreis – auch
// nicht unter „Ohne Thema“. Sie zählen an einer kleinen Kugel an fester Stelle (ohne Anker). Ist ein Gedanke
// fertig, fliegt ein Punkt von der Kugel zu seinem Kreis (`MapLandings`).

/// Was die Kugel unter der Zahl sagt
public enum MapInboxStatus: Sendable, Equatable {
    /// mindestens einer wird gerade verschriftlicht oder geordnet
    case ordering
    case network
    case key
    case limit
    case budget
    /// Ton gesichert, nicht verschriftlicht
    case attention

    /// Gehört der Gedanke in den Eingang (in Arbeit oder wartend)?
    public static func isPending(_ state: ThoughtState) -> Bool {
        switch state {
        case .recording, .captured, .transcribing, .transcribed, .structuring: true
        case .waitingNetwork, .waitingKey, .waitingLimit, .waitingBudget, .needsAttention: true
        case .done, .empty: false
        }
    }

    /// Zustand der Kugel: Läuft etwas, „wird geordnet“. Sonst der Grund, der am ehesten etwas vom Nutzer braucht
    /// (Schlüssel, dann nicht verschriftlicht, dann Netz, Limit, Kontingent). nil = nichts im Eingang.
    public static func of<S: Sequence>(_ states: S) -> MapInboxStatus? where S.Element == ThoughtState {
        var best: MapInboxStatus?
        var rank = Int.max
        for state in states {
            let (status, r): (MapInboxStatus?, Int) = switch state {
            case .recording, .captured, .transcribing, .transcribed, .structuring: (.ordering, 0)
            case .waitingKey: (.key, 1)
            case .needsAttention: (.attention, 2)
            case .waitingNetwork: (.network, 3)
            case .waitingLimit: (.limit, 4)
            case .waitingBudget: (.budget, 5)
            case .done, .empty: (nil, .max)
            }
            if let status, r < rank {
                best = status
                rank = r
                if r == 0 { break }
            }
        }
        return best
    }
}

/// Buchführung der Flüge von der Kugel zu den Kreisen (ohne Uhr und ohne Oberfläche – die Zeit kommt von außen).
///
/// - `observe` meldet, wer gerade im Eingang ist. Wer ihn verlässt, wartet (`awaiting`), bis die Karte ihn zeigt –
///   die Anordnung rechnet im Hintergrund. Bis dahin zählt er an der Kugel weiter, damit die Zahl nicht springt.
/// - `place` plant für jeden, der jetzt auf der Karte steht, einen Flug. Mehrere fliegen nacheinander (`stagger`,
///   eine Welle startet höchstens über `spread`); die Zahl an der Kugel sinkt mit jedem Abflug.
/// - Ohne Bewegung (reduzierte Bewegung, Fokus auf ein Thema) gibt es keinen Flug: Der Gedanke erscheint einfach.
/// - Kommt ein fertiger Gedanke nicht auf die Karte (gelöscht, leer), fällt er nach `patience` heraus.
public struct MapLandings: Sendable, Equatable {
    public struct Flight: Sendable, Equatable, Identifiable {
        /// Gedanke
        public var id: String
        /// Kreis, zu dem er fliegt
        public var topicID: String
        public var launch: Date
        public var duration: TimeInterval

        public var land: Date { launch.addingTimeInterval(duration) }

        /// 0 … 1 während des Flugs; nil davor und danach
        public func progress(at now: Date) -> CGFloat? {
            let t = now.timeIntervalSince(launch)
            guard t >= 0, t < duration else { return nil }
            return CGFloat(t / duration)
        }
    }

    /// Abstand zweier Abflüge
    public static let stagger: TimeInterval = 0.3
    /// eine Welle startet höchstens über so lange (viele auf einmal: dichter hintereinander)
    public static let spread: TimeInterval = 2.4
    public static let duration: TimeInterval = 0.9
    /// mehr auf einmal erscheinen ohne Flug
    public static let maxFlights = 12
    /// so lange wartet ein fertiger Gedanke höchstens auf die Karte
    public static let patience: TimeInterval = 8
    /// so lange leuchtet die Landung nach
    public static let glow: TimeInterval = 0.9

    /// zuletzt gemeldeter Eingang
    public private(set) var pending: Set<String> = []
    /// fertig, aber noch nicht auf der Karte: seit wann
    public private(set) var awaiting: [String: Date] = [:]
    /// geplante und laufende Flüge (bis zum Ende des Nachleuchtens)
    public private(set) var flights: [Flight] = []
    private var started = false

    public init() {}

    /// Eingang melden (bei jedem Neuzeichnen). Das erste Melden merkt nur – wer schon fertig war, fliegt nicht.
    public mutating func observe(pending ids: Set<String>, now: Date) {
        guard started else {
            started = true
            pending = ids
            return
        }
        for id in pending where !ids.contains(id) { awaiting[id] = now }
        for id in ids {
            // wieder in Arbeit („Erneut ordnen“): wartet nicht mehr und fliegt nicht
            awaiting[id] = nil
        }
        if !ids.isEmpty { flights.removeAll { ids.contains($0.id) } }
        pending = ids
        awaiting = awaiting.filter { now.timeIntervalSince($0.value) <= Self.patience }
        flights.removeAll { now.timeIntervalSince($0.land) > Self.glow }
    }

    /// Wer wartet und jetzt auf der Karte steht (`target` liefert seinen Kreis, nil = noch nicht da), bekommt einen
    /// Flug – der Reihe nach, wie sie fertig wurden. `animate` false: ohne Flug. Gibt die neuen Flüge zurück.
    @discardableResult
    public mutating func place(animate: Bool, now: Date, target: (String) -> String?) -> [Flight] {
        guard !awaiting.isEmpty else { return [] }
        let ready = awaiting.compactMap { id, since in target(id).map { (id: id, since: since, topic: $0) } }
            .sorted { $0.since != $1.since ? $0.since < $1.since : $0.id < $1.id }
        guard !ready.isEmpty else { return [] }
        for item in ready { awaiting[item.id] = nil }
        guard animate else { return [] }
        let queued = flights.reduce(0) { $0 + ($1.launch > now ? 1 : 0) }
        let wave = ready.prefix(max(0, Self.maxFlights - queued))
        guard !wave.isEmpty else { return [] }
        let step = min(Self.stagger, Self.spread / Double(wave.count + queued))
        var next = now
        if let last = flights.map(\.launch).max() { next = max(now, last.addingTimeInterval(step)) }
        var added: [Flight] = []
        for item in wave {
            let flight = Flight(id: item.id, topicID: item.topic, launch: next, duration: Self.duration)
            flights.append(flight)
            added.append(flight)
            next = next.addingTimeInterval(step)
        }
        return added
    }

    /// Zahl an der Kugel: in Arbeit, fertig aber noch nicht auf der Karte, noch nicht abgeflogen
    public func count(at now: Date) -> Int {
        pending.count + awaiting.count + flights.reduce(0) { $0 + ($1.launch > now ? 1 : 0) }
    }

    /// Schon abgeflogen (für den kleinen Stoß der Kugel bei jedem Abflug)
    public func launched(at now: Date) -> Int {
        flights.reduce(0) { $0 + ($1.launch <= now ? 1 : 0) }
    }

    /// Gedanken, deren Punkt noch nicht gelandet ist (geplant oder in der Luft)
    public func unlanded(at now: Date) -> [Flight] {
        flights.filter { $0.land > now }
    }

    /// Läuft noch etwas (Flug oder Nachleuchten)?
    public func isRunning(at now: Date) -> Bool {
        flights.contains { now.timeIntervalSince($0.land) < Self.glow }
    }

    /// Nächster Zeitpunkt, an dem sich etwas ändert (Abflug, Landung, Ende des Nachleuchtens, Ende des Wartens).
    public func nextEvent(after now: Date) -> Date? {
        var best: Date?
        func consider(_ t: Date) {
            guard t > now else { return }
            if best.map({ t < $0 }) ?? true { best = t }
        }
        for flight in flights {
            consider(flight.launch)
            consider(flight.land)
            consider(flight.land.addingTimeInterval(Self.glow))
        }
        if let oldest = awaiting.values.min() { consider(oldest.addingTimeInterval(Self.patience + 0.01)) }
        return best
    }
}
