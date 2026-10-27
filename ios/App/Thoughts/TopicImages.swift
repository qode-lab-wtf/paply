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
/// - Endgültig gelöscht wird nur auf Ereignisse: Der Speicher hat ein Thema gespeichert entfernt (gelöscht oder
///   mangels Gedanken aufgeräumt, `ThoughtStore.removedTopics` → `topicsRemoved`), oder der Nutzer entfernt ein Bild.
///   Bis dahin bleibt die Datei eines gelöschten Themas liegen – angezeigt wird sie nicht mehr; scheitert das
///   Speichern, ist das Thema samt Bild einfach wieder da.
/// - Zusammenführen (`TopicImageFile.plan`, nur Verschieben): Hat das Ziel kein Bild, wird das der Quelle zu seinem
///   (atomar umbenannt, sobald das Zusammenführen gespeichert ist); Widerrufen benennt es zurück. Hat das Ziel eines,
///   parkt das der Quelle (`.parked-<id>.jpg`) – Widerrufen bringt es zurück, nach einem Neustart ist es weg. Zu jedem
///   Zeitpunkt liegt mindestens eine Kopie da.
/// - Abgleich beim Start (`TopicImageFile.reconcile`): nur mit einer vollständig gelesenen Themenliste aus einem
///   Speicher-Aufruf (`ThoughtStore.topicsSnapshot`); räumt auf, was ein Abbruch hinterlassen hat. Im Zweifel nichts.
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
    /// in dieser Sitzung geparkt (Zusammenführen in ein Ziel mit Bild)
    @ObservationIgnored private var parked: Set<String> = []
    /// beim Start vorgefunden geparkt (frühere Sitzung) – bis zum Abgleich
    @ObservationIgnored private var staleParked: Set<String> = []
    /// in dieser Sitzung angefasst: Der Abgleich lässt sie, wie sie sind
    @ObservationIgnored private var touched: Set<String> = []
    @ObservationIgnored private var cache: [String: UIImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// Änderungszähler je Thema: ein Lesen, das während einer Änderung lief, wird verworfen
    @ObservationIgnored private var edits: [String: Int] = [:]
    /// nur im Speicher: JPEG je Kennung bzw. geparkt
    @ObservationIgnored private var memory: [String: Data] = [:]
    @ObservationIgnored private var memoryParked: [String: Data] = [:]
    @ObservationIgnored private var aliases: [String: String] = [:]
    /// letzte Themenliste des Modells (nil = noch keine) und ob sie der Stand des Speichers ist
    @ObservationIgnored private var topics: [Topic]?
    @ObservationIgnored private var topicsSaved = false
    /// vollständig gelesene Liste für den Abgleich, bis der Ordner gelesen ist; der Abgleich läuft einmal je Start
    @ObservationIgnored private var snapshot: [Topic]?
    @ObservationIgnored private var reconciled = false
    /// übernommene Bilder (Zusammenführen): Ziel → Quelle, nur in dieser Sitzung (Widerrufen)
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
        reconcileIfPossible()
        planIfPossible()
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

    /// Neues Bild (schon zugeschnitten) für ein Thema. Ein übernommenes Bild geht dabei zurück zu seiner Quelle (geparkt),
    /// damit Widerrufen des Zusammenführens es ihr wiedergeben kann.
    func setImage(_ jpeg: Data, for topicID: String) {
        guard TopicImageFile.isValidID(topicID), let image = UIImage(data: jpeg) else { return }
        prepare()
        guard stored != nil else { return } // noch nicht lesbar: nichts schreiben
        var url: URL?
        if let directory {
            guard ProtectedData.isReadable, let imageURL = Self.imageURL(topicID, in: directory) else { return }
            url = imageURL
        }
        handBackAdopted(topicID)
        touch(topicID)
        cache[topicID] = image.preparingForDisplay() ?? image
        stored?.insert(topicID)
        parked.remove(topicID)
        if let directory, let url {
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

    /// Bild eines Themas entfernen (das Symbol erscheint wieder). Ein übernommenes geht zurück zu seiner Quelle (geparkt).
    func removeImage(for topicID: String) {
        guard TopicImageFile.isValidID(topicID) else { return }
        if !handBackAdopted(topicID) { discard(topicID) }
        revision += 1
    }

    /// Meldung des Modells: alle Themen (auch zusammengeführte). `persistent`: angebundenes Modell; `saved`: Stand des
    /// Speichers (sonst Stand der Oberfläche vor dem Speichern). Nur Verschieben – nie Löschen (`TopicImageFile.plan`).
    func update(topics: [Topic], persistent: Bool, saved: Bool, from model: AnyObject) {
        guard accepts(persistent: persistent, from: model) else { return }
        let next = Dictionary(topics.compactMap { topic in topic.mergedInto.map { (topic.id, $0) } }, uniquingKeysWith: { a, _ in a })
        if next != aliases {
            aliases = next
            revision += 1
        }
        self.topics = topics
        topicsSaved = saved
        planIfPossible()
    }

    /// Abgleich beim Start: Themenliste und „vollständig gelesen“ aus einem Speicher-Aufruf (`topicsSnapshot`).
    /// Unvollständig → nichts; der nächste Aufruf mit vollständiger Liste gleicht ab (einmal je Start).
    func reconcile(topics: [Topic], complete: Bool, from model: AnyObject) {
        guard directory != nil, accepts(persistent: true, from: model), complete, !reconciled else { return }
        snapshot = topics
        reconcileIfPossible()
        planIfPossible()
    }

    /// Ereignis des Speichers: Diese Themen sind gespeichert entfernt (gelöscht, mangels Gedanken aufgeräumt) –
    /// ihre Bilder samt geparkten sind endgültig weg.
    func topicsRemoved(_ ids: Set<String>, from model: AnyObject) {
        guard accepts(persistent: true, from: model) else { return }
        let gone = ids.filter(TopicImageFile.isValidID)
        guard !gone.isEmpty else { return }
        prepare() // Ordner zuerst lesen, sonst käme eine gleich gelöschte Datei beim Lesen wieder in die Liste
        for id in gone { discard(id) }
        adopted = adopted.filter { !gone.contains($0.key) && !gone.contains($0.value) }
        revision += 1
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

    private func planIfPossible() {
        guard let topics, let current = stored else { return }
        apply(TopicImageFile.plan(images: current, parked: parked, adopted: adopted, topics: topics, saved: topicsSaved))
    }

    private func reconcileIfPossible() {
        guard !reconciled, let snapshot, let current = stored else { return }
        reconciled = true
        self.snapshot = nil
        let plan = TopicImageFile.reconcile(images: current, parked: staleParked, keep: touched, topics: snapshot, complete: true)
        staleParked.subtract(plan.restore.union(plan.dropParked))
        apply(plan)
    }

    /// Reihenfolge: erst zurück und übernehmen (umbenennen), dann parken, zuletzt löschen
    private func apply(_ plan: TopicImageFile.Plan) {
        guard !plan.isEmpty else { return }
        for (target, source) in plan.giveBack.sorted(by: { $0.key < $1.key }) {
            relocate(target, to: source)
            adopted[target] = nil
        }
        for id in plan.restore.sorted() { unpark(id) }
        for (target, source) in plan.adopt.sorted(by: { $0.key < $1.key }) {
            relocate(source, to: target)
            adopted[target] = source
        }
        for id in plan.park.sorted() { park(id) }
        for id in plan.delete.sorted() { discard(id) }
        for id in plan.dropParked.sorted() { dropParked(id) }
        revision += 1
    }

    private func touch(_ ids: String...) {
        for id in ids {
            edits[id, default: 0] += 1
            touched.insert(id)
        }
    }

    /// Bild umbenennen: `from` → `to` (Zusammenführen übernehmen bzw. zurückgeben)
    private func relocate(_ from: String, to: String) {
        guard TopicImageFile.isValidID(from), TopicImageFile.isValidID(to) else { return }
        touch(from, to)
        let image = cache.removeValue(forKey: from)
        cache[to] = image
        stored?.remove(from)
        stored?.insert(to)
        if let directory {
            guard let a = Self.imageURL(from, in: directory), let b = Self.imageURL(to, in: directory) else { return }
            perform { Self.rename(a, to: b) }
            if image == nil { preload([to]) }
        } else if let data = memory.removeValue(forKey: from) {
            memory[to] = data
        }
    }

    /// Übernommenes Bild des Ziels geht geparkt zurück zur Quelle (das Ziel bekommt ein neues oder keins mehr).
    /// false = nichts übernommen.
    @discardableResult
    private func handBackAdopted(_ target: String) -> Bool {
        guard let source = adopted.removeValue(forKey: target), stored?.contains(target) == true else { return false }
        touch(target, source)
        cache[target] = nil
        stored?.remove(target)
        parked.insert(source)
        if let directory {
            guard let a = Self.imageURL(target, in: directory), let b = Self.parkedURL(source, in: directory) else { return true }
            perform { Self.rename(a, to: b) }
        } else if let data = memory.removeValue(forKey: target) {
            memoryParked[source] = data
        }
        return true
    }

    /// Bild samt geparktem endgültig weg – nur auf Ereignisse und beim Abgleich
    private func discard(_ id: String) {
        touch(id)
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
        touch(id)
        cache[id] = nil
        stored?.remove(id)
        parked.insert(id)
        if let directory {
            guard let from = Self.imageURL(id, in: directory), let to = Self.parkedURL(id, in: directory) else { return }
            perform { Self.rename(from, to: to) }
        } else if let data = memory.removeValue(forKey: id) {
            memoryParked[id] = data
        }
    }

    private func unpark(_ id: String) {
        touch(id)
        parked.remove(id)
        staleParked.remove(id)
        stored?.insert(id)
        if let directory {
            guard let from = Self.parkedURL(id, in: directory), let to = Self.imageURL(id, in: directory) else { return }
            perform { Self.rename(from, to: to) }
            preload([id])
        } else if let data = memoryParked.removeValue(forKey: id) {
            memory[id] = data
        }
    }

    /// Geparktes endgültig weg (Abgleich: Thema weg, zusammengeführt oder mit neuerem Bild)
    private func dropParked(_ id: String) {
        touch(id)
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

    /// Atomar umbenennen (`rename(2)`, ersetzt ein vorhandenes Ziel): Davor liegt die Datei unter dem alten Namen,
    /// danach unter dem neuen – nie unter keinem.
    nonisolated private static func rename(_ from: URL, to: URL) {
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        if Darwin.rename(from.path, to.path) != 0 {
            Diag.log("topic.image.move.failed", ["errno": .i(Int(errno))])
        }
    }
}
