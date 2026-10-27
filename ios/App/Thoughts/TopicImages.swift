import Foundation
import Observation
import PaplyKit
import UIKit

/// Was das Bearbeiten-Blatt mit dem Bild eines Themas macht
enum TopicImageChange: Equatable {
    case unchanged
    /// schon zugeschnitten (`TopicImages.process`)
    case set(Data)
    case remove
}

/// Bild statt Symbol für ein Thema (Bearbeiten-Blatt → „Bild wählen …“).
///
/// Ablage: `topic-images/<topicID>.jpg` neben den Gedanken-Daten (`ThoughtsEnvironment.root`, wie `topic-colors.json`
/// und `map-anchors.json`) – quadratisch, höchstens 512 px, JPEG ohne Metadaten (`TopicImageFile`). Atomar geschrieben,
/// gleicher Dateischutz wie die Gedanken, nicht im iCloud-Backup. Die Bilder gehen nie an die KI und nie ins Netz:
/// Sie sind kein Teil von Gedanken, Themen oder Anfragen.
///
/// - Aliasse zeigen das Bild ihres Ziels (`image(for:)` löst auf).
/// - Aufräumen nach der Themenliste (`TopicImageFile.plan`): Ein gelöschtes Thema verliert sein Bild sofort aus
///   der Anzeige; die Datei parkt (`.parked-<id>.jpg`), bis die Liste gespeichert ist – scheitert das Speichern,
///   kommt das Thema samt Bild zurück. Ein zusammengeführtes parkt es bis zum nächsten Start: Widerrufen bringt es
///   zurück, danach ist es weg. Hat das Ziel kein Bild, übernimmt es das Bild des aufgehenden Themas (Widerrufen
///   nimmt es wieder weg).
/// - Eine noch unbekannte Themenliste (Speicher nicht gelesen) ändert nichts; eine vollständig gelesene leere
///   Liste heißt: alle Bilder sind verwaist.
/// - Vor dem ersten Entsperren wird weder gelesen noch geschrieben (`ProtectedData`).
/// - Beispieldaten (`-PaplyPreviewData`, `-PaplyMany`, `-PaplyCount`, `-PaplyEmpty`) und SwiftUI-Vorschauen halten
///   Bilder nur im Speicher und nehmen nur Meldungen der Beispielmodelle an – die Ablage bleibt unberührt.
/// - Dekodierte Bilder bleiben im Speicher (je ≤ 1 MB); bei einer Speicherwarnung fallen sie weg und werden bei
///   Bedarf im Hintergrund neu gelesen. Gelesen wird nie auf dem Hauptthread.
@MainActor
@Observable
final class TopicImages {
    static let shared = TopicImages(directory: storageDirectory)

    /// steigt bei jeder Änderung (Bild gesetzt, entfernt, geladen; Aliasse) – für Neuzeichnen
    private(set) var revision = 0

    /// nil = nur im Speicher
    @ObservationIgnored private let directory: URL?
    /// Kennungen mit Bild; nil = Ordner noch nicht gelesen
    @ObservationIgnored private var stored: Set<String>?
    /// in dieser Sitzung geparkt (Zusammenführen)
    @ObservationIgnored private var parked: Set<String> = []
    /// beim Start vorgefunden geparkt (frühere Sitzung) – weg, sobald die Themen bekannt sind
    @ObservationIgnored private var staleParked: Set<String> = []
    @ObservationIgnored private var cache: [String: UIImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// Änderungszähler je Thema: ein Lesen, das während einer Änderung lief, wird verworfen
    @ObservationIgnored private var edits: [String: Int] = [:]
    /// nur im Speicher: JPEG je Kennung bzw. geparkt
    @ObservationIgnored private var memory: [String: Data] = [:]
    @ObservationIgnored private var memoryParked: [String: Data] = [:]
    @ObservationIgnored private var aliases: [String: String] = [:]
    /// letzte vollständige Themenliste des geladenen Modells (nil = noch unbekannt)
    @ObservationIgnored private var topics: [Topic]?
    /// `topics` ist gespeichert (aus dem Speicher gelesen) – erst dann wird endgültig gelöscht
    @ObservationIgnored private var topicsConfirmed = false
    /// übernommene Bilder (Zusammenführen): Ziel → Quelle. Fällt weg, sobald das Ziel ein eigenes Bild bekommt
    /// oder seines verliert.
    @ObservationIgnored private var adopted: [String: String] = [:]
    @ObservationIgnored private var io: Task<Void, Never>?
    @ObservationIgnored private var waitsForUnlock = false
    @ObservationIgnored private var indexRequested = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// nur im Speicher: das Beispielmodell, dessen Meldungen zählen (das erste; weitere Exemplare, die SwiftUI beim
    /// erneuten Aufbau von `RootView` anlegt und verwirft, hätten andere Themen und räumten sonst alles weg)
    @ObservationIgnored private var source: ObjectIdentifier?

    init(directory: URL?) {
        self.directory = directory
        if directory == nil { stored = [] }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropDecoded() }
        }
    }

    private static var storageDirectory: URL? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        #if DEBUG
        if ThoughtsDebug.previewData || ProcessInfo.processInfo.arguments.contains("-PaplyEmpty") { return nil }
        #endif
        return ThoughtsEnvironment.root.appendingPathComponent(TopicImageFile.directoryName, isDirectory: true)
    }

    // MARK: Lesen

    /// Bild eines Themas (Aliasse → Ziel), im Speicher zwischengespeichert. nil = kein Bild – oder noch nicht
    /// gelesen; dann steigt `revision`, sobald es da ist.
    func image(for topicID: String?) -> UIImage? {
        _ = revision
        guard let id = resolved(topicID) else { return nil }
        if let image = cache[id] { return image }
        guard let stored else {
            requestIndex()
            return nil
        }
        guard stored.contains(id) else { return nil }
        if directory == nil {
            guard let data = memory[id], let image = UIImage(data: data) else { return nil }
            cache[id] = image
            return image
        }
        preload([id])
        return nil
    }

    /// Hat das Thema (bzw. sein Ziel) ein Bild?
    func hasImage(for topicID: String?) -> Bool {
        _ = revision
        guard let id = resolved(topicID) else { return false }
        return cache[id] != nil || (stored?.contains(id) ?? false)
    }

    private func resolved(_ topicID: String?) -> String? {
        guard let topicID, !TopicPalette.isNeutral(topicID) else { return nil }
        return TopicImageFile.resolve(topicID, aliases: aliases)
    }

    /// Ordner lesen, sobald die Daten lesbar sind (beim Start; mehrfach aufrufbar)
    func prepare() {
        guard stored == nil, let directory else { return }
        guard ProtectedData.isReadable else {
            if !waitsForUnlock {
                waitsForUnlock = true
                ProtectedData.whenReadable { [weak self] _ in
                    self?.waitsForUnlock = false
                    self?.prepare()
                }
            }
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let scan = TopicImageFile.scan(names)
        stored = scan.images
        staleParked = scan.parked
        retireIfPossible()
        preload(Array(stored ?? []))
        revision += 1
    }

    private func requestIndex() {
        guard !indexRequested else { return }
        indexRequested = true
        // nicht während eine Ansicht gezeichnet wird
        Task { @MainActor [weak self] in self?.prepare() }
    }

    // MARK: Ändern

    /// Bild zuschneiden (quadratisch, ≤ 512 px, JPEG 0,8, ohne Metadaten) – im Hintergrund. nil = kein lesbares Bild.
    nonisolated static func process(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { TopicImageFile.squareJPEG(from: data) }.value
    }

    /// Ergebnis des Bearbeiten-Blatts übernehmen
    func apply(_ change: TopicImageChange, to topicID: String) {
        switch change {
        case .unchanged: break
        case .set(let jpeg): setImage(jpeg, for: topicID)
        case .remove: removeImage(for: topicID)
        }
    }

    /// Neues Bild (schon zugeschnitten) für ein Thema
    func setImage(_ jpeg: Data, for topicID: String) {
        guard TopicImageFile.isValidID(topicID), let image = UIImage(data: jpeg) else { return }
        prepare()
        guard stored != nil else { return } // noch nicht lesbar: nichts schreiben
        edits[topicID, default: 0] += 1
        cache[topicID] = image.preparingForDisplay() ?? image
        stored?.insert(topicID)
        parked.remove(topicID)
        adopted[topicID] = nil
        if let directory {
            guard ProtectedData.isReadable, let url = Self.imageURL(topicID, in: directory) else { return }
            let parkedURL = Self.parkedURL(topicID, in: directory)
            perform {
                Self.write(jpeg, to: url, directory: directory)
                if let parkedURL { try? FileManager.default.removeItem(at: parkedURL) }
            }
        } else {
            memory[topicID] = jpeg
            memoryParked[topicID] = nil
        }
        revision += 1
    }

    /// Bild eines Themas entfernen (das Symbol erscheint wieder)
    func removeImage(for topicID: String) {
        guard TopicImageFile.isValidID(topicID) else { return }
        discard(topicID)
        revision += 1
    }

    /// Meldung des Modells: alle Themen (auch zusammengeführte). `persistent`: angebundenes Modell; `loaded`: die
    /// Themenliste ist vollständig gelesen – erst dann wird aufgeräumt (auch eine leere Liste zählt dann);
    /// `confirmed`: die Liste ist gespeichert (sonst Stand der Oberfläche vor dem Speichern – dann wird nur geparkt).
    func update(topics: [Topic], persistent: Bool, loaded: Bool, confirmed: Bool, from model: AnyObject) {
        guard accepts(persistent: persistent, from: model) else { return }
        let next = Dictionary(topics.compactMap { topic in topic.mergedInto.map { (topic.id, $0) } }, uniquingKeysWith: { a, _ in a })
        if next != aliases {
            aliases = next
            revision += 1
        }
        guard loaded else { return }
        self.topics = topics
        topicsConfirmed = confirmed
        retireIfPossible()
    }

    /// Ablage nimmt nur das angebundene Modell an, der Speicher nur das erste Beispielmodell
    private func accepts(persistent: Bool, from model: AnyObject) -> Bool {
        guard persistent == (directory != nil) else { return false }
        guard directory == nil else { return true }
        let id = ObjectIdentifier(model)
        if let source, source != id { return false }
        source = id
        return true
    }

    // MARK: Aufräumen

    private func retireIfPossible() {
        guard let topics, let current = stored else { return }
        let inMemory = directory == nil
        let plan = TopicImageFile.plan(images: current, parked: inMemory ? Set(memoryParked.keys) : parked,
                                       staleParked: inMemory ? [] : staleParked, adopted: adopted,
                                       topics: topics, confirmed: topicsConfirmed)
        guard !plan.isEmpty else { return }
        // Übernehmen vor dem Parken: Die Kopie entsteht aus dem Bild der Quelle, bevor es geparkt wird
        for (target, source) in plan.adopt.sorted(by: { $0.key < $1.key }) { adopt(target, from: source) }
        for id in plan.unadopt { discard(id) }
        for id in plan.delete { discard(id) }
        for id in plan.park { park(id) }
        for id in plan.restore { unpark(id) }
        for id in plan.dropParked { dropParked(id) }
        revision += 1
    }

    /// Ziel ohne Bild übernimmt das Bild der Quelle (Kopie; die Quelle parkt ihres gleich danach)
    private func adopt(_ target: String, from source: String) {
        guard TopicImageFile.isValidID(target) else { return }
        edits[target, default: 0] += 1
        stored?.insert(target)
        adopted[target] = source
        if let image = cache[source] { cache[target] = image }
        if let directory {
            guard let from = Self.imageURL(source, in: directory), let to = Self.imageURL(target, in: directory) else { return }
            perform { Self.copy(from, to: to, directory: directory) }
            preload([target])
        } else if let data = memory[source] {
            memory[target] = data
        }
    }

    private func discard(_ id: String) {
        edits[id, default: 0] += 1
        cache[id] = nil
        stored?.remove(id)
        parked.remove(id)
        staleParked.remove(id)
        adopted[id] = nil
        if let directory {
            let urls = [Self.imageURL(id, in: directory), Self.parkedURL(id, in: directory)].compactMap { $0 }
            perform { for url in urls { try? FileManager.default.removeItem(at: url) } }
        } else {
            memory[id] = nil
            memoryParked[id] = nil
        }
    }

    private func park(_ id: String) {
        edits[id, default: 0] += 1
        cache[id] = nil
        stored?.remove(id)
        adopted[id] = nil
        if let directory {
            guard let from = Self.imageURL(id, in: directory), let to = Self.parkedURL(id, in: directory) else { return }
            parked.insert(id)
            perform { Self.move(from, to: to) }
        } else if let data = memory.removeValue(forKey: id) {
            memoryParked[id] = data
        }
    }

    private func unpark(_ id: String) {
        edits[id, default: 0] += 1
        parked.remove(id)
        staleParked.remove(id)
        stored?.insert(id)
        if let directory {
            guard let from = Self.parkedURL(id, in: directory), let to = Self.imageURL(id, in: directory) else { return }
            perform { Self.move(from, to: to) }
            preload([id])
        } else if let data = memoryParked.removeValue(forKey: id) {
            memory[id] = data
        }
    }

    /// Geparktes endgültig weg (Thema gespeichert gelöscht, Widerrufen vorbei, überholt)
    private func dropParked(_ id: String) {
        parked.remove(id)
        staleParked.remove(id)
        if let directory {
            guard let url = Self.parkedURL(id, in: directory) else { return }
            perform { try? FileManager.default.removeItem(at: url) }
        } else {
            memoryParked[id] = nil
        }
    }

    private func dropDecoded() {
        guard !cache.isEmpty else { return }
        for id in cache.keys { edits[id, default: 0] += 1 }
        cache.removeAll()
        revision += 1
    }

    // MARK: Dateien (der Reihe nach, im Hintergrund)

    private struct Decoded: @unchecked Sendable {
        let id: String
        let edit: Int
        let image: UIImage
    }

    /// Bilder im Hintergrund lesen und vordekodieren; nach Schreib- und Verschiebevorgängen, die vorher angestoßen
    /// wurden
    private func preload(_ ids: [String]) {
        guard let directory else { return }
        let wanted = ids.filter { cache[$0] == nil && !loading.contains($0) }
        guard !wanted.isEmpty else { return }
        loading.formUnion(wanted)
        let snapshot = wanted.map { (id: $0, edit: edits[$0, default: 0]) }
        perform { [weak self] in
            var decoded: [Decoded] = []
            for item in snapshot {
                guard let url = Self.imageURL(item.id, in: directory), let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { continue }
                decoded.append(Decoded(id: item.id, edit: item.edit, image: image.preparingForDisplay() ?? image))
            }
            await self?.finishLoading(wanted, decoded)
        }
    }

    private func finishLoading(_ ids: [String], _ decoded: [Decoded]) {
        loading.subtract(ids)
        var changed = false
        for item in decoded where edits[item.id, default: 0] == item.edit && stored?.contains(item.id) == true {
            cache[item.id] = item.image
            changed = true
        }
        if changed { revision += 1 }
    }

    private func perform(_ operation: @escaping @Sendable () async -> Void) {
        let previous = io
        io = Task.detached(priority: .utility) {
            await previous?.value
            await operation()
        }
    }

    nonisolated private static func imageURL(_ id: String, in directory: URL) -> URL? {
        TopicImageFile.fileName(for: id).map { directory.appendingPathComponent($0) }
    }

    nonisolated private static func parkedURL(_ id: String, in directory: URL) -> URL? {
        TopicImageFile.parkedFileName(for: id).map { directory.appendingPathComponent($0) }
    }

    nonisolated private static func write(_ data: Data, to url: URL, directory: URL) {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                var folder = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
            }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Diag.log("topic.image.write.failed", ["error": .s(String(describing: type(of: error)))])
        }
    }

    nonisolated private static func copy(_ from: URL, to: URL, directory: URL) {
        guard let data = try? Data(contentsOf: from) else {
            Diag.log("topic.image.copy.failed")
            return
        }
        write(data, to: to, directory: directory)
    }

    nonisolated private static func move(_ from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return }
        try? fm.removeItem(at: to)
        do {
            try fm.moveItem(at: from, to: to)
        } catch {
            Diag.log("topic.image.move.failed", ["error": .s(String(describing: type(of: error)))])
        }
    }
}
