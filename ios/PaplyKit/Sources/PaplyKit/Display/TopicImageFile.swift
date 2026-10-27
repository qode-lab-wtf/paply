import CoreGraphics
import Foundation
import ImageIO

/// Bild statt Symbol für ein Thema: Ablage, Zuschnitt und Aufräumregeln. Die Bilder bleiben auf dem Gerät –
/// sie gehen nie an die KI und nie ins Netz (kein Teil von Gedanken, Themen oder Anfragen).
///
/// Ablage: `topic-images/<topicID>.jpg` neben den Gedanken-Daten. Ein zusammengeführtes Thema „parkt“ sein Bild
/// bis zum nächsten Start als `.parked-<topicID>.jpg` – Widerrufen bringt es zurück, danach ist es weg. Ebenso
/// parkt das Bild eines gelöschten Themas, bis die Themenliste gespeichert ist; erst dann ist es endgültig weg.
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

    /// Was mit den Bildern geschieht, wenn sich die Themenliste ändert (`plan`)
    public struct Plan: Sendable, Equatable {
        /// Bild endgültig löschen (samt geparktem): Thema laut gespeicherter Liste weg
        public var delete: Set<String> = []
        /// Bild parken: zusammengeführt (Widerrufen möglich) oder gelöscht, aber noch nicht gespeichert
        public var park: Set<String> = []
        /// geparktes Bild zurück: Thema wieder eigenständig (Widerrufen, Speichern gescheitert)
        public var restore: Set<String> = []
        /// nur das geparkte Bild endgültig löschen (Thema gespeichert weg, aus einer früheren Sitzung, überholt)
        public var dropParked: Set<String> = []
        /// Ziel → Quelle: Ein Ziel ohne Bild übernimmt beim Zusammenführen das Bild des aufgehenden Themas
        public var adopt: [String: String] = [:]
        /// übernommene Bilder wieder entfernen (Zusammenführen widerrufen oder nicht gespeichert)
        public var unadopt: Set<String> = []

        public init() {}

        public var isEmpty: Bool { self == Plan() }
    }

    /// Aufräumplan für eine Themenliste.
    ///
    /// - `topics`: alle Themen samt Aliassen (`mergedInto`). nil = noch unbekannt (Speicher nicht gelesen) → nichts
    ///   ändern. Eine leere Liste heißt dagegen „vollständig gelesen und leer“: Alle Bilder sind verwaist.
    /// - `confirmed`: Die Liste ist gespeichert (aus dem Speicher gelesen). Sonst ist es der Stand der Oberfläche
    ///   vor dem Speichern – dann wird nichts endgültig gelöscht, sondern geparkt (scheitert das Speichern, kommt
    ///   das Thema samt Bild zurück).
    /// - `images`: Themen mit Bild. `parked`: in dieser Sitzung geparkt (Widerrufen möglich). `staleParked`: aus
    ///   einer früheren Sitzung geparkt (Widerrufen vorbei). `adopted`: Ziel → Quelle übernommener Bilder.
    ///
    /// Zusammenführen: Das Bild der Quelle parkt (Widerrufen bringt es zurück). Hat das Ziel kein Bild, übernimmt es
    /// das Bild der Quelle (bei mehreren die erste in der Reihenfolge der Liste); wird die Quelle wieder eigenständig,
    /// fällt das übernommene Bild wieder weg.
    public static func plan(images: Set<String>, parked: Set<String> = [], staleParked: Set<String> = [],
                            adopted: [String: String] = [:], topics: [Topic]?, confirmed: Bool) -> Plan {
        guard let topics else { return Plan() }
        var plan = Plan()
        let byID = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func standalone(_ id: String) -> Bool { byID[id].map { $0.mergedInto == nil } ?? false }

        // Bilder: Thema weg → löschen (gespeichert) bzw. parken; zusammengeführt → parken
        for id in images {
            guard let topic = byID[id] else {
                if confirmed { plan.delete.insert(id) } else { plan.park.insert(id) }
                continue
            }
            if topic.mergedInto != nil { plan.park.insert(id) }
        }
        // Geparkte: eigenständig → zurück (oder überholt, wenn es schon ein Bild gibt); sonst nach gespeicherter
        // Liste weg, aus früheren Sitzungen auch zusammengeführte (Widerrufen vorbei)
        for id in parked.union(staleParked) where !plan.delete.contains(id) {
            if standalone(id) {
                if images.contains(id) { plan.dropParked.insert(id) } else { plan.restore.insert(id) }
            } else if confirmed, byID[id] == nil || staleParked.contains(id) {
                plan.dropParked.insert(id)
            }
        }
        // Zusammenführen widerrufen: Was ein Ziel von einer wieder eigenständigen Quelle übernommen hat, fällt weg
        for (target, source) in adopted where standalone(source) && standalone(target) && images.contains(target) {
            plan.unadopt.insert(target)
        }
        // Zusammengeführt: Ein Ziel ohne Bild übernimmt das Bild der (ersten) Quelle
        var aliases: [String: String] = [:]
        for topic in topics { if let target = topic.mergedInto { aliases[topic.id] = target } }
        for topic in topics where topic.mergedInto != nil && images.contains(topic.id) {
            let target = resolve(topic.id, aliases: aliases)
            guard target != topic.id, isValidID(target), standalone(target), !images.contains(target),
                  !plan.restore.contains(target), plan.adopt[target] == nil else { continue }
            plan.adopt[target] = topic.id
        }
        return plan
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
