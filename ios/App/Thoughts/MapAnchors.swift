import Foundation
import PaplyKit

/// Gemerkte Plätze der Themen auf der Gedanken-Karte (`MapLayout`).
///
/// Ablage: `map-anchors.json` neben den Gedanken-Daten (`ThoughtsEnvironment.root`, dort liegen auch
/// `topics.json` und das Ledger) – gleicher Dateischutz, gleiche Sicherung, geht mit den Gedanken weg.
/// Geschrieben wird gebündelt (0,5 s nach der letzten Änderung), atomar und der Reihe nach.
///
/// Sicherheit:
/// - Ist die Datei da, aber nicht lesbar (vor dem ersten Entsperren), wird nie geschrieben – sonst gingen die
///   Plätze verloren. Erneut gelesen wird frühestens nach 5 s.
/// - Beispieldaten (`-PaplyPreviewData`, `-PaplyMany`, `-PaplyCount`, `-PaplyEmpty`) merken nur im Speicher: Ihre Themen
///   würden sonst beim Speichern die echten Anker verdrängen.
/// - Die Karte meldet nur, wenn das Modell geladen ist (sonst sähen alle Themen gelöscht aus).
@MainActor
final class MapAnchors {
    static let shared = MapAnchors(url: storageURL)

    private enum State {
        case notLoaded
        case loaded
        case blocked(since: Date)
    }

    private let url: URL?
    private var state: State = .notLoaded
    private var current: [String: MapAnchor] = [:]
    private var pending: Task<Void, Never>?
    private var writes: Task<Void, Never>?

    /// nil = nur im Speicher
    init(url: URL?) {
        self.url = url
        if url == nil { state = .loaded }
    }

    private static var storageURL: URL? {
        #if DEBUG
        if ThoughtsDebug.previewData || ProcessInfo.processInfo.arguments.contains("-PaplyEmpty") { return nil }
        #endif
        return ThoughtsEnvironment.root.appendingPathComponent(MapAnchorFile.fileName)
    }

    /// Aktuelle Plätze (lädt beim ersten Zugriff)
    var anchors: [String: MapAnchor] {
        loadIfNeeded()
        return current
    }

    /// Neuer vollständiger Stand aus der Karte; Themen, die darin fehlen, fallen beim Speichern weg.
    func remember(_ anchors: [String: MapAnchor]) {
        loadIfNeeded()
        guard case .loaded = state, anchors != current else { return }
        current = anchors
        scheduleSave()
    }

    private func loadIfNeeded() {
        switch state {
        case .loaded:
            return
        case .blocked(let since) where Date().timeIntervalSince(since) < 5:
            return
        default:
            break
        }
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
    }

    private func scheduleSave() {
        guard let url else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
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
