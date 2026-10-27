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

    // MARK: Aufräumen

    private func topic(_ id: String, mergedInto: String? = nil) -> Topic {
        Topic(id: id, title: id, icon: .sparkles, owner: .user, mergedInto: mergedInto)
    }

    @Test func deletedTopicsLoseTheirImageMergedOnesArePark() {
        let topics = [topic("t_live"), topic("t_alias", mergedInto: "t_live")]
        let plan = TopicImageFile.plan(images: ["t_live", "t_alias", "t_gone"], topics: topics, confirmed: true)
        #expect(plan.delete == ["t_gone"])
        #expect(plan.park == ["t_alias"])
        #expect(plan.adopt.isEmpty) // das Ziel hat schon ein Bild
    }

    @Test func unknownTopicsChangeNothing() {
        let plan = TopicImageFile.plan(images: ["t_a", "t_b"], parked: ["t_c"], staleParked: ["t_d"], topics: nil, confirmed: true)
        #expect(plan.isEmpty)
    }

    /// Das letzte Thema verschwindet (z. B. automatisch, weil es keinen Gedanken mehr trägt): vollständig gelesen
    /// und leer ist nicht „unbekannt“ – die Bilder sind verwaist, auch nach einem Neustart
    @Test func emptyKnownTopicListRetiresEverything() {
        let saved = TopicImageFile.plan(images: ["t_a", "t_b"], staleParked: ["t_c"], topics: [], confirmed: true)
        #expect(saved.delete == ["t_a", "t_b"])
        #expect(saved.dropParked == ["t_c"])
        // noch nicht gespeichert: nur parken
        let unsaved = TopicImageFile.plan(images: ["t_a"], topics: [], confirmed: false)
        #expect(unsaved.delete.isEmpty && unsaved.park == ["t_a"])
    }

    /// Thema gelöscht, aber `topics.json` noch nicht geschrieben: Das Bild parkt nur. Scheitert das Speichern,
    /// kommt das Thema zurück – und mit ihm sein Bild. Gelingt es, ist das Bild danach endgültig weg.
    @Test func deletionWaitsForTheSavedTopicList() {
        // 1. Oberfläche: Thema weg, noch nicht gespeichert
        let optimistic = TopicImageFile.plan(images: ["t_a", "t_b"], topics: [topic("t_b")], confirmed: false)
        #expect(optimistic.park == ["t_a"])
        #expect(optimistic.delete.isEmpty && optimistic.dropParked.isEmpty)
        // geparkt bleibt geparkt, solange nicht gespeichert
        let still = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], topics: [topic("t_b")], confirmed: false)
        #expect(still.isEmpty)
        // 2a. Speichern gescheitert: Der Speicher liefert das Thema wieder – das Bild kommt zurück
        let failed = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], topics: [topic("t_a"), topic("t_b")], confirmed: true)
        #expect(failed.restore == ["t_a"])
        #expect(failed.delete.isEmpty && failed.dropParked.isEmpty)
        // 2b. gespeichert: endgültig weg
        let saved = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], topics: [topic("t_b")], confirmed: true)
        #expect(saved.dropParked == ["t_a"])
        #expect(saved.restore.isEmpty)
    }

    @Test func undoneMergeRestoresParkedImage() {
        let topics = [topic("t_a"), topic("t_b", mergedInto: "t_a")]
        let plan = TopicImageFile.plan(images: [], parked: ["t_a", "t_b", "t_gone"], topics: topics, confirmed: true)
        #expect(plan.restore == ["t_a"])
        #expect(plan.dropParked == ["t_gone"]) // t_b bleibt geparkt: Widerrufen ist noch möglich
    }

    @Test func earlierSessionParkedIsRetiredOnceSaved() {
        let topics = [topic("t_a"), topic("t_b", mergedInto: "t_a")]
        // nur mit gespeicherter Liste; eigenständige kommen zurück (z. B. Absturz vor dem Speichern)
        let saved = TopicImageFile.plan(images: [], staleParked: ["t_a", "t_b", "t_gone"], topics: topics, confirmed: true)
        #expect(saved.restore == ["t_a"])
        #expect(saved.dropParked == ["t_b", "t_gone"])
        let unsaved = TopicImageFile.plan(images: [], staleParked: ["t_b", "t_gone"], topics: topics, confirmed: false)
        #expect(unsaved.isEmpty)
    }

    /// A (mit Bild) geht in B (ohne Bild) auf: B übernimmt As Bild, As Bild parkt. Widerrufen: A bekommt sein Bild
    /// zurück, B verliert das übernommene.
    @Test func mergeIntoTopicWithoutImageAdoptsTheImage() {
        let merged = [topic("t_a", mergedInto: "t_b"), topic("t_b")]
        let plan = TopicImageFile.plan(images: ["t_a"], topics: merged, confirmed: false)
        #expect(plan.park == ["t_a"])
        #expect(plan.adopt == ["t_b": "t_a"])
        // danach (B hat jetzt ein Bild): nichts mehr zu tun
        let after = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], adopted: ["t_b": "t_a"], topics: merged, confirmed: true)
        #expect(after.isEmpty)
        // Widerrufen
        let undone = [topic("t_a"), topic("t_b")]
        let back = TopicImageFile.plan(images: ["t_b"], parked: ["t_a"], adopted: ["t_b": "t_a"], topics: undone, confirmed: false)
        #expect(back.restore == ["t_a"])
        #expect(back.unadopt == ["t_b"])
        #expect(back.delete.isEmpty && back.park.isEmpty)
    }

    @Test func adoptionPicksOneSourceAndFollowsAliasChains() {
        // zwei Quellen mit Bild: die erste der Liste; A → B → C: C übernimmt
        let topics = [topic("t_a", mergedInto: "t_b"), topic("t_x", mergedInto: "t_c"), topic("t_b", mergedInto: "t_c"), topic("t_c")]
        let plan = TopicImageFile.plan(images: ["t_a", "t_x"], topics: topics, confirmed: false)
        #expect(plan.adopt == ["t_c": "t_a"])
        #expect(plan.park == ["t_a", "t_x"])
        // Ziel hat ein Bild: keine Übernahme
        let own = TopicImageFile.plan(images: ["t_a", "t_c"], topics: topics, confirmed: false)
        #expect(own.adopt.isEmpty)
        // Quelle gelöscht statt eigenständig: das Ziel behält das übernommene Bild
        let gone = TopicImageFile.plan(images: ["t_c"], parked: ["t_a"], adopted: ["t_c": "t_a"], topics: [topic("t_c")], confirmed: true)
        #expect(gone.unadopt.isEmpty && gone.dropParked == ["t_a"])
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
