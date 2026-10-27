import Foundation
import Observation
import PaplyKit

/// Gemerkte Plätze der Themen auf der Gedanken-Karte (`MapLayout`).
///
/// Ablage: `map-anchors.json` neben den Gedanken-Daten (`ThoughtsEnvironment.root`, dort liegen auch
/// `topics.json` und das Ledger) – gleicher Dateischutz, gleiche Sicherung, geht mit den Gedanken weg.
/// Geschrieben wird gebündelt (0,5 s nach der letzten Änderung), atomar und der Reihe nach.
///
/// Sicherheit (Buchführung in `MapAnchorState`, PaplyKit, dort getestet):
/// - Gelesen wird erst, wenn die Daten lesbar sind (`ProtectedData.whenReadable`, nach dem ersten Entsperren).
///   Bis dahin ist `isReady` false: Die Karte zeichnet nichts und legt nichts neu an – sonst bekämen alle
///   Themen neue Plätze und sprängen nach dem Entsperren zurück.
/// - Ist die Datei danach trotzdem nicht lesbar (Ein-/Ausgabefehler), wird nie geschrieben – sonst gingen die
///   Plätze verloren. Die Karte zeichnet dann ohne gemerkte Plätze; erneut gelesen wird frühestens nach 5 s.
/// - Jedes Lesen erhöht `revision` (beobachtet): Die Karte rechnet mit den gelesenen Plätzen neu, und eine
///   Anordnung, die noch mit dem alten Stand gerechnet wurde, merkt nichts mehr (`remember(_:revision:)`).
/// - Beispieldaten (`-PaplyPreviewData`, `-PaplyMany`, `-PaplyCount`, `-PaplyEmpty`) merken nur im Speicher: Ihre
///   Themen würden sonst beim Speichern die echten Anker verdrängen.
/// - Die Karte meldet nur, wenn das Modell geladen ist (sonst sähen alle Themen gelöscht aus).
@MainActor
@Observable
final class MapAnchors {
    static let shared = MapAnchors(url: storageURL)

    /// Plätze sind gelesen (oder stehen fest) – erst dann zeichnet die Karte
    private(set) var isReady = false
    /// steigt mit jedem Lesen; gehört in jede Anfrage an die Karte (`MapRequest.anchorRevision`)
    private(set) var revision = 0

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var state: MapAnchorState
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var writes: Task<Void, Never>?

    /// nil = nur im Speicher
    init(url: URL?) {
        self.url = url
        state = MapAnchorState(inMemory: url == nil)
        publish()
    }

    private static var storageURL: URL? {
        #if DEBUG
        if ThoughtsDebug.previewData || ProcessInfo.processInfo.arguments.contains("-PaplyEmpty") { return nil }
        #endif
        return ThoughtsEnvironment.root.appendingPathComponent(MapAnchorFile.fileName)
    }

    /// Aktuelle Plätze (leer, solange nicht `isReady`)
    var anchors: [String: MapAnchor] { state.anchors }

    /// Laden anstoßen: sofort, wenn die Daten lesbar sind, sonst nach dem ersten Entsperren. Mehrfach
    /// aufrufbar (aus `onAppear` der Karte); nach einem Lesefehler frühestens alle 5 s erneut.
    func prepare() {
        switch state.prepare(now: Date()) {
        case .readAfterUnlock:
            ProtectedData.whenReadable { [weak self] _ in self?.load() }
        case .readNow:
            load()
        case .nothing:
            break
        }
    }

    /// Neuer vollständiger Stand aus der Karte, gerechnet mit den Plätzen von `revision`; Themen, die darin
    /// fehlen, fallen beim Speichern weg. Ältere Revisionen und ungelesene Dateien werden nie gemerkt.
    func remember(_ anchors: [String: MapAnchor], revision: Int) {
        guard state.remember(anchors, revision: revision) else { return }
        scheduleSave()
    }

    private func load() {
        guard let url else { return }
        let loaded = MapAnchorFile.load(from: url)
        if loaded == .unreadable { Diag.log("map.anchors.unreadable", [:]) }
        state.apply(loaded, now: Date())
        publish()
    }

    /// Beobachtete Felder nachziehen (nur bei Änderung, damit die Karte nicht unnötig neu zeichnet)
    private func publish() {
        if isReady != state.isReady { isReady = state.isReady }
        if revision != state.revision { revision = state.revision }
    }

    private func scheduleSave() {
        guard let url else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.state.mayWrite else { return }
            let snapshot = self.state.anchors
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
