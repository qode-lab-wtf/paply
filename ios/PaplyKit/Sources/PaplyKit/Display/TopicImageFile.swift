import CoreGraphics
import Foundation
import ImageIO

/// Bild statt Symbol für ein Thema: Ablage, Zuschnitt und Aufräumregeln. Die Bilder bleiben auf dem Gerät –
/// sie gehen nie an die KI und nie ins Netz (kein Teil von Gedanken, Themen oder Anfragen).
///
/// Ablage: `topic-images/<topicID>.jpg` neben den Gedanken-Daten. Zusammenführen verschiebt das Bild der Quelle zum
/// Ziel ohne Bild (Widerrufen verschiebt es zurück); hat das Ziel eines, „parkt“ das der Quelle bis zum nächsten Start
/// als `.parked-<topicID>.jpg`. Jeder Schritt ist ein atomares Umbenennen – zu jedem Zeitpunkt liegt mindestens eine
/// Kopie da. Endgültig gelöscht wird nur auf Ereignisse (Thema gespeichert entfernt, Bild entfernt) und beim Abgleich
/// mit einer vollständig gelesenen Themenliste (`reconcile`).
public enum TopicImageFile {
    public static let directoryName = "topic-images"
    /// längste Kante des gespeicherten Bilds
    public static let maxPixel = 512
    public static let jpegQuality = 0.8
    static let parkedPrefix = ".parked-"
    static let suffix = ".jpg"

    /// Nur einfache Kennungen werden zu Dateinamen (keine Pfade, keine versteckten Dateien).
    public static func isValidID(_ id: String) -> Bool {
        guard (1...80).contains(id.utf8.count), id.first != "." else { return false }
        return id.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95 || byte == 45
        }
    }

    public static func fileName(for topicID: String) -> String? {
        isValidID(topicID) ? topicID + suffix : nil
    }

    public static func parkedFileName(for topicID: String) -> String? {
        isValidID(topicID) ? parkedPrefix + topicID + suffix : nil
    }

    /// Inhalt des Ordners lesen: Kennungen mit Bild und geparkte. Fremdes (halbe Schreibvorgänge) zählt nicht.
    public static func scan(_ names: [String]) -> (images: Set<String>, parked: Set<String>) {
        var images: Set<String> = []
        var parked: Set<String> = []
        for name in names where name.hasSuffix(suffix) {
            let stem = String(name.dropLast(suffix.count))
            if stem.hasPrefix(parkedPrefix) {
                let id = String(stem.dropFirst(parkedPrefix.count))
                if isValidID(id) { parked.insert(id) }
            } else if isValidID(stem) {
                images.insert(stem)
            }
        }
        return (images, parked)
    }

    // MARK: Aufräumen

    /// Was mit den Bildern geschieht – in der Sitzung (`plan`) nur Verschieben, beim Abgleich (`reconcile`) auch Löschen
    public struct Plan: Sendable, Equatable {
        /// Ziel → Quelle: Das Bild der Quelle wird das Bild des Ziels (verschoben, nicht kopiert)
        public var adopt: [String: String] = [:]
        /// Ziel → Quelle: übernommenes Bild zurück zur wieder eigenständigen Quelle (verschoben)
        public var giveBack: [String: String] = [:]
        /// Bild parken: zusammengeführt in ein Ziel mit eigenem Bild (Widerrufen bringt es zurück)
        public var park: Set<String> = []
        /// geparktes Bild zurück: Thema wieder eigenständig
        public var restore: Set<String> = []
        /// nur beim Abgleich: Bild samt geparktem endgültig löschen
        public var delete: Set<String> = []
        /// nur beim Abgleich: geparktes endgültig löschen
        public var dropParked: Set<String> = []

        public init() {}

        public var isEmpty: Bool { self == Plan() }
    }

    /// Plan in der Sitzung für eine Themenliste der Oberfläche oder des Speichers. Er verschiebt nur und löscht nie –
    /// eine veraltete, leere oder noch nicht gespeicherte Liste kann kein Bild verlieren. Ein gelöschtes Thema behält
    /// seine Datei, bis der Speicher es gespeichert entfernt hat (`ThoughtStore.removedTopics`); angezeigt wird sie
    /// ohnehin nicht mehr.
    ///
    /// - `images`: Themen mit Bild. `parked`: in dieser Sitzung geparkt. `adopted`: Ziel → Quelle übernommener Bilder.
    /// - `saved`: Die Liste ist der Stand des Speichers. Nur dann übernimmt ein Ziel das Bild – es liegt also nie bei
    ///   einem Ziel, dessen Zusammenführen nicht gespeichert ist.
    ///
    /// Zusammengeführt (Quelle → Ziel): Hat das Ziel kein Bild, übernimmt es das der (ersten) Quelle; sonst parkt
    /// es. Wieder eigenständig (Widerrufen, Speichern gescheitert): geparktes zurück, übernommenes zurück zur Quelle.
    public static func plan(images: Set<String>, parked: Set<String> = [], adopted: [String: String] = [:],
                            topics: [Topic], saved: Bool) -> Plan {
        let byID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func standalone(_ id: String) -> Bool { byID[id].map { $0.mergedInto == nil } ?? false }
        var plan = Plan()
        for (target, source) in adopted
        where standalone(source) && standalone(target) && images.contains(target) && !images.contains(source) {
            plan.giveBack[target] = source
        }
        let returning = Set(plan.giveBack.values)
        for id in parked where standalone(id) && !images.contains(id) && !returning.contains(id) {
            plan.restore.insert(id)
        }
        mergedImages(images: images, topics: topics, byID: byID, plan: &plan) { _, free in
            free ? (saved ? .adopt : .wait) : .park
        }
        return plan
    }

    /// Abgleich mit einer Themenliste aus EINEM Speicher-Aufruf (`ThoughtStore.topicsSnapshot`) – nur, wenn sie
    /// vollständig gelesen ist (`complete`); sonst geschieht nichts, im Zweifel wird nie gelöscht. Räumt auf, was ein
    /// Abbruch oder eine frühere Sitzung hinterlassen hat; Widerrufen ist nach einem Neustart vorbei:
    /// - Bild eines Themas, das es nicht gibt → löschen
    /// - Bild eines zusammengeführten Themas → das Ziel ohne Bild übernimmt es, sonst löschen
    /// - geparktes: Thema eigenständig und ohne Bild → zurück; sonst (weg, zusammengeführt, neueres Bild) → löschen
    ///
    /// `images`: alle Themen mit Bild; `parked`: aus früheren Sitzungen geparkt; `keep`: in dieser Sitzung angefasst –
    /// bleibt, wie es ist.
    public static func reconcile(images: Set<String>, parked: Set<String>, keep: Set<String> = [], topics: [Topic],
                                 complete: Bool) -> Plan {
        guard complete else { return Plan() }
        let byID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func standalone(_ id: String) -> Bool { byID[id].map { $0.mergedInto == nil } ?? false }
        var plan = Plan()
        for id in parked where !keep.contains(id) {
            if standalone(id), !images.contains(id) { plan.restore.insert(id) } else { plan.dropParked.insert(id) }
        }
        for id in images where byID[id] == nil && !keep.contains(id) { plan.delete.insert(id) }
        mergedImages(images: images, topics: topics, byID: byID, plan: &plan) { id, free in
            keep.contains(id) ? .wait : free ? .adopt : .delete
        }
        return plan
    }

    private enum MergedImage { case adopt, park, delete, wait }

    /// Bilder zusammengeführter Themen, in der Reihenfolge der Liste: `decide(id, frei)` – frei = das Ziel ist
    /// eigenständig, hat kein Bild und übernimmt noch keines
    private static func mergedImages(images: Set<String>, topics: [Topic], byID: [String: Topic], plan: inout Plan,
                                     decide: (String, Bool) -> MergedImage) {
        var aliases: [String: String] = [:]
        for topic in topics { if let target = topic.mergedInto { aliases[topic.id] = target } }
        for topic in topics where topic.mergedInto != nil && images.contains(topic.id) {
            let target = resolve(topic.id, aliases: aliases)
            let free = target != topic.id && isValidID(target) && byID[target]?.mergedInto == nil && byID[target] != nil
                && !images.contains(target) && !plan.restore.contains(target) && plan.giveBack[target] == nil
                && plan.adopt[target] == nil
            switch decide(topic.id, free) {
            case .adopt: plan.adopt[target] = topic.id
            case .park: plan.park.insert(topic.id)
            case .delete: plan.delete.insert(topic.id)
            case .wait: break
            }
        }
    }

    /// Thema samt Alias-Kette auflösen (Aliasse → Ziel)
    public static func resolve(_ id: String, aliases: [String: String]) -> String {
        var current = id
        var seen: Set<String> = [id]
        while let next = aliases[current], seen.insert(next).inserted {
            current = next
        }
        return current
    }

    // MARK: Zuschnitt

    /// Quadratisch mittig zugeschnitten, Kante höchstens `maxPixel` (nie vergrößert), Ausrichtung aus den
    /// Metadaten angewandt, sRGB, als JPEG ohne Metadaten (kein Ort, keine Kamera). Durchsichtiges wird weiß.
    /// nil = kein lesbares Bild.
    public static func squareJPEG(from data: Data, maxPixel: Int = maxPixel, quality: Double = jpegQuality) -> Data? {
        guard maxPixel > 0, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        // Nur so groß decodieren, dass die kurze Kante nach dem Zuschnitt noch `maxPixel` hat
        let short = min(width, height), long = max(width, height)
        let target = min(short, Double(maxPixel))
        let thumbnailSize = min(8_192, max(1, Int((long * target / short).rounded(.up))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(decoded.width, decoded.height)
        guard side > 0 else { return nil }
        let crop = CGRect(x: (decoded.width - side) / 2, y: (decoded.height - side) / 2, width: side, height: side)
        guard let square = decoded.cropping(to: crop) else { return nil }
        let edge = min(side, maxPixel)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        context.draw(square, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        guard let output = context.makeImage() else { return nil }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }
}
