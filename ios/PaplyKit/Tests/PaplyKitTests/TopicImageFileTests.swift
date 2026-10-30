import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PaplyKit

@Suite("Oberfläche: Bild statt Symbol")
struct TopicImageFileTests {
    // MARK: Bilder bauen und lesen

    /// links Rot, rechts Blau; optional durchsichtig, mit Ausrichtung und Ort in den Metadaten
    private func image(width: Int, height: Int, type: String = "public.jpeg", orientation: Int? = nil,
                       gps: Bool = false, transparent: Bool = false) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        let cg = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                                                         kCGImagePropertyGPSLongitude: 13.40, kCGImagePropertyGPSLongitudeRef: "E"]
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFMake: "Testkamera"]
        }
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private struct Decoded {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        /// (r, g, b) an x, y – y = 0 ist oben
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
    }

    private func decode(_ data: Data) -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                    bytesPerRow: cg.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return Decoded(width: cg.width, height: cg.height, pixels: pixels)
    }

    private func isRed(_ c: (Int, Int, Int)) -> Bool { c.0 > 200 && c.1 < 60 && c.2 < 60 }
    private func isBlue(_ c: (Int, Int, Int)) -> Bool { c.0 < 60 && c.1 < 60 && c.2 > 200 }
    private func isWhite(_ c: (Int, Int, Int)) -> Bool { c.0 > 235 && c.1 > 235 && c.2 > 235 }

    // MARK: Zuschnitt

    @Test func largePhotoBecomesSquare512() throws {
        let out = try #require(TopicImageFile.squareJPEG(from: image(width: 2_000, height: 1_500)))
        let decoded = try #require(decode(out))
        #expect(decoded.width == 512 && decoded.height == 512)
        // mittig: links Rot, rechts Blau
        #expect(isRed(decoded.rgb(100, 256)))
        #expect(isBlue(decoded.rgb(412, 256)))
        #expect(out.count < 120_000)
    }

    @Test func smallPhotoIsNeverEnlarged() throws {
        let out = try #require(TopicImageFile.squareJPEG(from: image(width: 300, height: 200, type: "public.png")))
        let decoded = try #require(decode(out))
        #expect(decoded.width == 200 && decoded.height == 200)
    }

    @Test func orientationIsApplied() throws {
        // 90° im Uhrzeigersinn: das linke Rot steht oben, das rechte Blau unten
        let out = try #require(TopicImageFile.squareJPEG(from: image(width: 400, height: 200, orientation: 6)))
        let decoded = try #require(decode(out))
        #expect(decoded.width == 200 && decoded.height == 200)
        #expect(isRed(decoded.rgb(100, 30)))
        #expect(isBlue(decoded.rgb(100, 170)))
    }

    @Test func metadataIsDropped() throws {
        let out = try #require(TopicImageFile.squareJPEG(from: image(width: 800, height: 600, gps: true)))
        let source = try #require(CGImageSourceCreateWithData(out as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
    }

    @Test func transparencyBecomesWhite() throws {
        let out = try #require(TopicImageFile.squareJPEG(from: image(width: 64, height: 64, type: "public.png", transparent: true)))
        let decoded = try #require(decode(out))
        #expect(isWhite(decoded.rgb(32, 32)))
    }

    @Test func garbageIsRejected() {
        #expect(TopicImageFile.squareJPEG(from: Data("kein Bild".utf8)) == nil)
        #expect(TopicImageFile.squareJPEG(from: Data()) == nil)
    }

    // MARK: Ablage

    @Test func onlySimpleIDsBecomeFileNames() {
        #expect(TopicImageFile.fileName(for: "t_0123abcd") == "t_0123abcd.jpg")
        #expect(TopicImageFile.fileName(for: "../topics") == nil)
        #expect(TopicImageFile.fileName(for: ".parked-x") == nil)
        #expect(TopicImageFile.fileName(for: "a/b") == nil)
        #expect(TopicImageFile.fileName(for: "") == nil)
        #expect(TopicImageFile.parkedFileName(for: "t_1") == ".parked-t_1.jpg")
    }

    @Test func scanSeparatesImagesParkedAndLeftovers() {
        let scan = TopicImageFile.scan(["t_a.jpg", ".parked-t_b.jpg", "t_c.jpg.tmp", ".tmp-1-t_d.jpg", "notes.txt", ".parked-../x.jpg"])
        #expect(scan.images == ["t_a"])
        #expect(scan.parked == ["t_b"])
    }

    // MARK: Aufräumen in der Sitzung – nur Verschieben, nie Löschen (vierte Prüfrunde)

    private func topic(_ id: String, mergedInto: String? = nil) -> Topic {
        Topic(id: id, title: id, icon: .sparkles, owner: .user, mergedInto: mergedInto)
    }

    /// Keine Themenliste – leer, veraltet, ungespeichert oder gespeichert – löscht in der Sitzung ein Bild
    @Test func sessionPlanNeverDeletes() {
        let lists: [[Topic]] = [[], [topic("t_b")], [topic("t_a", mergedInto: "t_b"), topic("t_b")]]
        for topics in lists {
            for saved in [false, true] {
                let plan = TopicImageFile.plan(images: ["t_a", "t_gone"], parked: ["t_x"], adopted: ["t_b": "t_a"],
                                               topics: topics, saved: saved)
                #expect(plan.delete.isEmpty && plan.dropParked.isEmpty, "\(topics.map(\.id)) \(saved)")
            }
        }
    }

    /// Vierte Prüfrunde (B): Vor dem ersten Entsperren ist die Liste leer – nichts geschieht
    @Test func emptyListBeforeUnlockChangesNothing() {
        #expect(TopicImageFile.plan(images: ["t_saved", "t_other"], topics: [], saved: true).isEmpty)
        #expect(TopicImageFile.reconcile(images: ["t_saved"], parked: ["t_p"], topics: [], complete: false).isEmpty)
        // nach dem Entsperren aus einem Aufruf: das Thema gibt es, sein Bild bleibt
        let unlocked = TopicImageFile.reconcile(images: ["t_saved"], parked: [], topics: [topic("t_saved")], complete: true)
        #expect(unlocked.isEmpty)
    }

    /// Gelöschtes Thema: Die Datei bleibt, bis der Speicher es gespeichert entfernt hat (Ereignis)
    @Test func deletedTopicKeepsItsFileUntilTheEvent() {
        let plan = TopicImageFile.plan(images: ["t_a", "t_b"], topics: [topic("t_b")], saved: false)
        #expect(plan.isEmpty)
    }

    @Test func mergeIntoTopicWithImageParksTheSource() {
        let merged = [topic("t_a", mergedInto: "t_b"), topic("t_b")]
        // schon in der Liste der Oberfläche: Parken verliert nichts
        let plan = TopicImageFile.plan(images: ["t_a", "t_b"], topics: merged, saved: false)
        #expect(plan.park == ["t_a"] && plan.adopt.isEmpty)
        // Widerrufen oder Speichern gescheitert: zurück
        let back = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], topics: [topic("t_a"), topic("t_b")], saved: false)
        #expect(back.restore == ["t_a"])
        // solange zusammengeführt: geparkt
        #expect(TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], topics: merged, saved: true).isEmpty)
    }

    /// Vierte Prüfrunde (C): A (mit Bild) geht in B (ohne Bild) auf – As Bild wird zu Bs verschoben, erst mit der
    /// gespeicherten Liste; Widerrufen verschiebt es zurück.
    @Test func mergeIntoTopicWithoutImageMovesTheImage() {
        let merged = [topic("t_a", mergedInto: "t_b"), topic("t_b")]
        // Oberfläche, noch nicht gespeichert: warten
        #expect(TopicImageFile.plan(images: ["t_a"], topics: merged, saved: false).isEmpty)
        // gespeichert: verschieben (kein Parken, keine Kopie)
        let saved = TopicImageFile.plan(images: ["t_a"], topics: merged, saved: true)
        #expect(saved.adopt == ["t_b": "t_a"])
        #expect(saved.park.isEmpty && saved.delete.isEmpty)
        // danach nichts mehr zu tun
        #expect(TopicImageFile.plan(images: ["t_b"], adopted: ["t_b": "t_a"], topics: merged, saved: true).isEmpty)
        // Widerrufen (schon in der Liste der Oberfläche): zurückverschieben
        let undone = [topic("t_a"), topic("t_b")]
        let back = TopicImageFile.plan(images: ["t_b"], adopted: ["t_b": "t_a"], topics: undone, saved: false)
        #expect(back.giveBack == ["t_b": "t_a"])
        #expect(back.delete.isEmpty && back.park.isEmpty && back.restore.isEmpty)
        // Quelle gelöscht statt eigenständig: B behält das Bild
        #expect(TopicImageFile.plan(images: ["t_b"], adopted: ["t_b": "t_a"], topics: [topic("t_b")], saved: true).isEmpty)
    }

    @Test func adoptionPicksOneSourceAndFollowsAliasChains() {
        // zwei Quellen mit Bild: die erste der Liste übernimmt, die zweite parkt; A → B → C: C übernimmt
        let topics = [topic("t_a", mergedInto: "t_b"), topic("t_x", mergedInto: "t_c"), topic("t_b", mergedInto: "t_c"), topic("t_c")]
        let plan = TopicImageFile.plan(images: ["t_a", "t_x"], topics: topics, saved: true)
        #expect(plan.adopt == ["t_c": "t_a"])
        #expect(plan.park == ["t_x"])
        // Ziel hat ein Bild: keine Übernahme, beide parken
        let own = TopicImageFile.plan(images: ["t_a", "t_c"], topics: topics, saved: true)
        #expect(own.adopt.isEmpty && own.park == ["t_a"])
    }

    // MARK: Abgleich beim Start

    @Test func reconcileNeedsACompleteList() {
        #expect(TopicImageFile.reconcile(images: ["t_a"], parked: ["t_b"], topics: [], complete: false).isEmpty)
        #expect(TopicImageFile.reconcile(images: ["t_a"], parked: ["t_b"], topics: [topic("t_c")], complete: false).isEmpty)
    }

    /// Vollständig gelesen: Bilder ohne Thema sind verwaist (auch bei leerer Liste); was diese Sitzung angefasst
    /// hat, bleibt
    @Test func reconcileRetiresOrphans() {
        let plan = TopicImageFile.reconcile(images: ["t_live", "t_gone", "t_new"], parked: ["t_old"], keep: ["t_new"],
                                            topics: [topic("t_live")], complete: true)
        #expect(plan.delete == ["t_gone"])
        #expect(plan.dropParked == ["t_old"])
        let empty = TopicImageFile.reconcile(images: ["t_a"], parked: ["t_b"], topics: [], complete: true)
        #expect(empty.delete == ["t_a"] && empty.dropParked == ["t_b"])
    }

    @Test func reconcileParkedFromEarlierSessions() {
        let topics = [topic("t_a"), topic("t_b", mergedInto: "t_a"), topic("t_c")]
        // eigenständig ohne Bild → zurück; zusammengeführt (Widerrufen vorbei), weg oder mit neuerem Bild → weg
        let plan = TopicImageFile.reconcile(images: ["t_c"], parked: ["t_a", "t_b", "t_c", "t_gone"], topics: topics, complete: true)
        #expect(plan.restore == ["t_a"])
        #expect(plan.dropParked == ["t_b", "t_c", "t_gone"])
    }

    // MARK: Abbruch-Zwischenstände (C): zu jedem Zeitpunkt mindestens eine Kopie

    /// Dateien im Ordner, wie `TopicImages` sie ändert (gleiche Reihenfolge: zurück, übernehmen, parken, löschen)
    private struct Folder: Equatable {
        var images: Set<String>
        var parked: Set<String> = []

        mutating func apply(_ plan: TopicImageFile.Plan) {
            for (target, source) in plan.giveBack where images.remove(target) != nil { images.insert(source) }
            for id in plan.restore where parked.remove(id) != nil { images.insert(id) }
            for (target, source) in plan.adopt where images.remove(source) != nil { images.insert(target) }
            for id in plan.park where images.remove(id) != nil { parked.insert(id) }
            images.subtract(plan.delete)
            parked.subtract(plan.delete.union(plan.dropParked))
        }

        /// Wiederanlauf: Abgleich mit der gespeicherten Liste (frühere Sitzung geparkt)
        func restarted(saved topics: [Topic]) -> Folder {
            var next = self
            next.apply(TopicImageFile.reconcile(images: images, parked: parked, topics: topics, complete: true))
            return next
        }

        var copies: Int { images.count + parked.count }
    }

    /// Zusammenführen A → B (B ohne Bild), dann Widerrufen – Abbruch nach jedem Schritt, gespeichert oder nicht
    @Test func mergeAndUndoNeverLoseTheImage() {
        let apart = [topic("t_a"), topic("t_b")]
        let merged = [topic("t_a", mergedInto: "t_b"), topic("t_b")]
        var folder = Folder(images: ["t_a"])
        // 1. Zusammenführen gespeichert, Bild noch nicht verschoben (Abbruch): der Start holt es nach
        #expect(folder.restarted(saved: merged) == Folder(images: ["t_b"]))
        // 2. gespeicherte Liste → verschieben
        let adopt = TopicImageFile.plan(images: folder.images, topics: merged, saved: true)
        folder.apply(adopt)
        #expect(folder == Folder(images: ["t_b"]))
        #expect(folder.restarted(saved: merged) == Folder(images: ["t_b"]))
        // 3. Widerrufen: Liste der Oberfläche → zurückverschieben, bevor gespeichert ist
        let back = TopicImageFile.plan(images: folder.images, adopted: adopt.adopt, topics: apart, saved: false)
        #expect(back.giveBack == ["t_b": "t_a"])
        var undone = folder
        undone.apply(back)
        #expect(undone == Folder(images: ["t_a"]))
        // 3a. Abbruch, Widerrufen nicht gespeichert: Der Start folgt der gespeicherten Liste (zusammengeführt)
        #expect(undone.restarted(saved: merged) == Folder(images: ["t_b"]))
        // 3b. Abbruch, Widerrufen gespeichert, aber noch nicht zurückverschoben: das Bild bleibt (bei B)
        #expect(folder.restarted(saved: apart).copies == 1)
        // 3c. alles gespeichert
        #expect(undone.restarted(saved: apart) == Folder(images: ["t_a"]))
    }

    /// Zusammenführen A → B (B mit Bild): As Bild parkt, erst nach dem gespeicherten Zusammenführen und einem Neustart
    /// ist es weg; Widerrufen bringt es zurück
    @Test func mergeIntoImageKeepsTheSourceUntilSaved() {
        let apart = [topic("t_a"), topic("t_b")]
        let merged = [topic("t_a", mergedInto: "t_b"), topic("t_b")]
        var folder = Folder(images: ["t_a", "t_b"])
        folder.apply(TopicImageFile.plan(images: folder.images, topics: merged, saved: false))
        #expect(folder == Folder(images: ["t_b"], parked: ["t_a"]))
        // Abbruch vor dem Speichern: A kommt samt Bild zurück
        #expect(folder.restarted(saved: apart) == Folder(images: ["t_a", "t_b"]))
        // gespeichert: nach dem Neustart weg
        #expect(folder.restarted(saved: merged) == Folder(images: ["t_b"]))
        // gespeichert, Parken noch nicht ausgeführt (Abbruch): ebenso
        #expect(Folder(images: ["t_a", "t_b"]).restarted(saved: merged) == Folder(images: ["t_b"]))
        // Widerrufen in der Sitzung
        folder.apply(TopicImageFile.plan(images: folder.images, parked: folder.parked, topics: apart, saved: false))
        #expect(folder == Folder(images: ["t_a", "t_b"]))
    }

    /// Thema gelöscht: Die Datei geht erst auf das Ereignis; Abbruch davor – gespeichert oder nicht – verliert nichts,
    /// was noch gebraucht wird
    @Test func deletionAbortsKeepWhatIsStillNeeded() {
        let folder = Folder(images: ["t_a", "t_b"])
        // nicht gespeichert: Das Thema gibt es noch, sein Bild auch
        #expect(folder.restarted(saved: [topic("t_a"), topic("t_b")]) == folder)
        // gespeichert, Ereignis verpasst: Der Start räumt auf
        #expect(folder.restarted(saved: [topic("t_b")]) == Folder(images: ["t_b"]))
    }

    @Test func aliasesResolveToTheirTarget() {
        let aliases = ["t_a": "t_b", "t_b": "t_c", "t_loop1": "t_loop2", "t_loop2": "t_loop1"]
        #expect(TopicImageFile.resolve("t_a", aliases: aliases) == "t_c")
        #expect(TopicImageFile.resolve("t_c", aliases: aliases) == "t_c")
        // Kreis: bricht ab statt zu hängen
        let loop = TopicImageFile.resolve("t_loop1", aliases: aliases)
        #expect(loop == "t_loop1" || loop == "t_loop2")
    }
}
