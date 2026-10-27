import Foundation

/// Farbplätze der Themen (Oberfläche der Gedanken).
///
/// Regeln:
/// - Ein Thema bekommt seinen Platz einmal, bei der ersten Sichtung, und behält ihn. Es wird nie umverteilt.
/// - Vergeben wird der erste freie Platz in `order` (Reihenfolge, in der nacheinander vergebene Plätze im
///   Farbkreis weit auseinanderliegen). Mehrere neue Themen kommen in Anlagereihenfolge dran.
/// - Zusammengeführte Themen (Alias, `mergedInto`) belegen keinen Platz; sie zeigen die Farbe ihres Ziels.
/// - Gelöschte Themen geben ihren Platz frei, die übrigen behalten ihren.
/// - Sind alle Plätze belegt, wiederholt sich der am wenigsten genutzte – nie der zuletzt vergebene.
/// - Taucht ein freigegebenes Thema in derselben Sitzung wieder auf (Widerrufen), bekommt es seinen alten
///   Platz zurück, falls der noch frei ist.
/// - Eine leere Themenliste ändert nichts (z. B. Speicher noch nicht gelesen): Es wird nichts freigegeben.
public struct TopicColorRegister: Sendable {
    /// Platz je lebendem Thema
    public private(set) var slots: [String: Int]
    /// zuletzt vergebener Platz
    public private(set) var last: Int?
    /// Alias → Ziel (nur im Speicher, kommt mit jeder Meldung neu)
    private var aliases: [String: String] = [:]
    /// in dieser Sitzung freigegebene Plätze (nur im Speicher)
    private var retired: [String: Int] = [:]

    public init(slots: [String: Int] = [:], last: Int? = nil) {
        self.slots = slots
        self.last = last
    }

    /// Platz eines Themas; Aliasse zeigen auf ihr Ziel. nil = (noch) unbekannt.
    public func slot(for id: String) -> Int? {
        var current = id
        var seen: Set<String> = []
        while let next = aliases[current], seen.insert(current).inserted {
            current = next
        }
        return slots[current]
    }

    /// Neuer Stand aller gespeicherten Themen (auch zusammengeführte). `order` ist eine Anordnung der Plätze
    /// 0 ..< n. Gibt true zurück, wenn sich Plätze geändert haben (dann speichern).
    @discardableResult
    public mutating func update(topics: [Topic], order: [Int]) -> Bool {
        aliases = [:]
        for topic in topics {
            if let target = topic.mergedInto, target != topic.id { aliases[topic.id] = target }
        }
        let living = topics.filter { $0.mergedInto == nil }
        guard !living.isEmpty, !order.isEmpty else { return false }
        let before = slots, beforeLast = last
        let valid = Set(order)
        let livingIDs = Set(living.map(\.id))
        for (id, slot) in slots where !livingIDs.contains(id) || !valid.contains(slot) {
            if valid.contains(slot) { retired[id] = slot }
            slots[id] = nil
        }
        let fresh = living
            .filter { slots[$0.id] == nil }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        var seenFresh: Set<String> = []
        for topic in fresh where seenFresh.insert(topic.id).inserted {
            var usage: [Int: Int] = [:]
            for slot in slots.values { usage[slot, default: 0] += 1 }
            let slot: Int
            if let old = retired[topic.id], valid.contains(old), (usage[old] ?? 0) == 0 {
                slot = old
            } else {
                slot = Self.pick(usage: usage, order: order, avoiding: last)
            }
            slots[topic.id] = slot
            retired[topic.id] = nil
            last = slot
        }
        return slots != before || last != beforeLast
    }

    /// Erster freier Platz in `order`; sind alle belegt, der am wenigsten genutzte außer `avoiding`.
    static func pick(usage: [Int: Int], order: [Int], avoiding: Int?) -> Int {
        let ranked = order.enumerated()
            .sorted { a, b in
                let x = usage[a.element] ?? 0, y = usage[b.element] ?? 0
                return x != y ? x < y : a.offset < b.offset
            }
            .map(\.element)
        guard let first = ranked.first else { return 0 }
        if (usage[first] ?? 0) == 0 { return first }
        return ranked.first { $0 != avoiding } ?? first
    }
}

extension TopicColorRegister: Equatable {
    /// Gleich = gleiche gespeicherte Plätze (Aliasse und Freigaben der Sitzung zählen nicht)
    public static func == (a: TopicColorRegister, b: TopicColorRegister) -> Bool {
        a.slots == b.slots && a.last == b.last
    }
}

/// Die Farbplätze als kleine JSON-Datei, atomar geschrieben:
///
///     {"last":3,"slots":{"t_…":0,"t_…":6},"version":1}
///
/// Lesen unterscheidet „gibt es nicht“ (darf geschrieben werden) von „nicht lesbar“ (z. B. vor dem ersten
/// Entsperren): Dann darf niemand die Datei überschreiben. Eine kaputte Datei zählt als leer – es sind nur
/// Farben, keine Inhalte.
public enum TopicColorFile {
    public static let fileName = "topic-colors.json"

    public enum Loaded: Sendable, Equatable {
        case missing
        case register(TopicColorRegister)
        case unreadable
        case damaged
    }

    private struct Payload: Codable {
        var version: Int
        var slots: [String: Int]
        var last: Int?
    }

    public static func load(from url: URL) -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .damaged }
        let slots = payload.slots.filter { $0.value >= 0 }
        return .register(TopicColorRegister(slots: slots, last: payload.last.flatMap { $0 >= 0 ? $0 : nil }))
    }

    /// Atomar (Nachbardatei, fsync, rename), Schlüssel sortiert – gleicher Stand ergibt gleiche Bytes.
    public static func save(_ register: TopicColorRegister, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(version: 1, slots: register.slots, last: register.last))
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) { try FileSafety.createDirectory(directory) }
        try FileSafety.writeAtomically(data, to: url)
    }
}
