import Foundation
import Observation
import PaplyKit

/// Gemerkte Plätze der Themen auf der Gedanken-Karte (`MapLayout`).
///
/// Ablage: `map-anchors.json` neben den Gedanken-Daten (`ThoughtsEnvironment.root`, dort liegen auch
/// `topics.json` und das Ledger) – gleicher Dateischutz, gleiche Sicherung, geht mit den Gedanken weg.
/// Geschrieben wird gebündelt (0,5 s nach der letzten Änderung), atomar und der Reihe nach.
///
/// Sicherheit:
/// - Gelesen wird erst, wenn die Daten lesbar sind (`ProtectedData.whenReadable`, nach dem ersten Entsperren).
///   Bis dahin ist `isReady` false: Die Karte zeichnet nichts und legt nichts neu an – sonst bekämen alle
///   Themen neue Plätze und sprängen nach dem Entsperren zurück.
/// - Ist die Datei danach trotzdem nicht lesbar (Ein-/Ausgabefehler), wird nie geschrieben – sonst gingen die
///   Plätze verloren. Die Karte zeichnet dann ohne gemerkte Plätze; erneut gelesen wird frühestens nach 5 s.
/// - Beispieldaten (`-PaplyPreviewData`, `-PaplyMany`, `-PaplyCount`, `-PaplyEmpty`) merken nur im Speicher: Ihre
///   Themen würden sonst beim Speichern die echten Anker verdrängen.
/// - Die Karte meldet nur, wenn das Modell geladen ist (sonst sähen alle Themen gelöscht aus).
@MainActor
@Observable
final class MapAnchors {
    static let shared = MapAnchors(url: storageURL)

    private enum State {
        /// noch nicht angefragt
        case idle
        /// wartet auf das erste Entsperren
        case waiting
        /// gelesen (oder keine bzw. kaputte Datei): darf schreiben
        case loaded
        /// Datei da, aber nicht lesbar: nie schreiben
        case blocked(since: Date)
    }

    /// Plätze sind gelesen (oder stehen fest) – erst dann zeichnet die Karte
    private(set) var isReady = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var state: State = .idle
    @ObservationIgnored private var current: [String: MapAnchor] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var writes: Task<Void, Never>?

    /// nil = nur im Speicher
    init(url: URL?) {
        self.url = url
        if url == nil {
            state = .loaded
            isReady = true
        }
    }

    private static var storageURL: URL? {
        #if DEBUG
        if ThoughtsDebug.previewData || ProcessInfo.processInfo.arguments.contains("-PaplyEmpty") { return nil }
        #endif
        return ThoughtsEnvironment.root.appendingPathComponent(MapAnchorFile.fileName)
    }

    /// Aktuelle Plätze (leer, solange nicht `isReady`)
    var anchors: [String: MapAnchor] { current }

    /// Laden anstoßen: sofort, wenn die Daten lesbar sind, sonst nach dem ersten Entsperren. Mehrfach
    /// aufrufbar (aus `onAppear` der Karte); nach einem Lesefehler frühestens alle 5 s erneut.
    func prepare() {
        switch state {
        case .idle:
            state = .waiting
            ProtectedData.whenReadable { [weak self] _ in self?.load() }
        case .blocked(let since) where Date().timeIntervalSince(since) >= 5:
            load()
        default:
            break
        }
    }

    /// Neuer vollständiger Stand aus der Karte; Themen, die darin fehlen, fallen beim Speichern weg.
    func remember(_ anchors: [String: MapAnchor]) {
        guard case .loaded = state, anchors != current else { return }
        current = anchors
        scheduleSave()
    }

    private func load() {
        guard let url else { return }
        switch MapAnchorFile.load(from: url) {
        case .anchors(let stored):
            current = stored
            state = .loaded
        case .missing, .damaged:
            current = [:]
            state = .loaded
        case .unreadable:
            state = .blocked(since: Date())
            Diag.log("map.anchors.unreadable", [:])
        }
        if !isReady { isReady = true }
    }

    private func scheduleSave() {
        guard let url else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            guard case .loaded = self.state else { return }
            let snapshot = self.current
            let previous = self.writes
            self.writes = Task.detached(priority: .utility) {
                await previous?.value
                do {
                    try MapAnchorFile.save(snapshot, to: url)
                } catch {
                    Diag.log("map.anchors.write.failed", ["error": .s(String(describing: type(of: error)))])
                }
            }
        }
    }
}
