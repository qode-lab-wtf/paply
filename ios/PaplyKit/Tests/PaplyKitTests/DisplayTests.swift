import Foundation
import Testing
@testable import PaplyKit

@Suite("Oberfläche: Themenfarben")
struct TopicColorRegisterTests {
    /// Reihenfolge wie in der App (Blau, Gold, Rosé, Mint, Violett, Koralle, Türkis, Orange, Indigo, Sand)
    private let order = [0, 6, 3, 7, 2, 4, 8, 5, 1, 9]

    private func topics(_ n: Int, start: Int = 0) -> [Topic] {
        (start..<start + n).map { i in
            Topic(id: "t\(String(format: "%02d", i))", title: "Thema \(i)", icon: .sparkles, owner: .ai,
                  createdAt: Date(timeIntervalSince1970: 1_000 + Double(i) * 60))
        }
    }

    @Test func firstSightingInCreationOrder() {
        var register = TopicColorRegister()
        // absichtlich ungeordnet gemeldet
        let all = topics(4).reversed()
        let changed = register.update(topics: Array(all), order: order)
        #expect(changed)
        #expect(register.slot(for: "t00") == 0)
        #expect(register.slot(for: "t01") == 6)
        #expect(register.slot(for: "t02") == 3)
        #expect(register.slot(for: "t03") == 7)
        #expect(register.last == 7)
        // gleicher Stand: keine Änderung
        let again = register.update(topics: topics(4), order: order)
        #expect(!again)
    }

    @Test func deletingAnOlderTopicKeepsTheOthers() {
        var register = TopicColorRegister()
        register.update(topics: topics(5), order: order)
        let before = register.slots
        var rest = topics(5)
        rest.remove(at: 1) // älteres Thema weg
        let changed = register.update(topics: rest, order: order)
        #expect(changed)
        for topic in rest { #expect(register.slot(for: topic.id) == before[topic.id]) }
        #expect(register.slot(for: "t01") == nil)
        // neues Thema bekommt den frei gewordenen Platz (erster freier in der Reihenfolge)
        let newer = topics(1, start: 9)
        register.update(topics: rest + newer, order: order)
        #expect(register.slot(for: "t09") == before["t01"])
    }

    @Test func aliasesTakeNoSlotAndShowTheirTarget() {
        var register = TopicColorRegister()
        var all = topics(3)
        register.update(topics: all, order: order)
        let target = register.slot(for: "t00")
        all[2].mergedInto = "t00"
        register.update(topics: all, order: order)
        #expect(register.slots["t02"] == nil)
        #expect(register.slot(for: "t02") == target)
        // Widerrufen: altes Thema bekommt seinen Platz zurück
        all[2].mergedInto = nil
        register.update(topics: all, order: order)
        #expect(register.slot(for: "t02") == 3)
    }

    @Test func noDuplicatesUpToTenAndNoImmediateRepeatAfterwards() {
        var register = TopicColorRegister()
        // mit vielen Aliassen dazwischen
        var all = topics(10)
        var aliases = topics(6, start: 20)
        for i in aliases.indices { aliases[i].mergedInto = "t00" }
        all += aliases
        register.update(topics: all, order: order)
        let used = (0..<10).compactMap { register.slot(for: "t\(String(format: "%02d", $0))") }
        #expect(Set(used).count == 10)
        // das elfte wiederholt, aber nicht den zuletzt vergebenen Platz
        let last = register.last
        register.update(topics: all + topics(1, start: 40), order: order)
        #expect(register.slot(for: "t40") != last)
        #expect(register.slot(for: "t40") == 0)
        // nach dem Zwölften immer noch keine direkte Wiederholung
        let last2 = register.last
        register.update(topics: all + topics(2, start: 40), order: order)
        #expect(register.slot(for: "t41") != last2)
    }

    @Test func emptyListFreesNothing() {
        var register = TopicColorRegister()
        register.update(topics: topics(3), order: order)
        let before = register
        let changed = register.update(topics: [], order: order)
        #expect(!changed)
        #expect(register == before)
    }

    @Test func storedSlotsAreNeverRedistributed() {
        // aus der Datei: t01 hat 9, t00 hat 6 – bleibt so, auch wenn die Reihenfolge anders vergeben würde
        var register = TopicColorRegister(slots: ["t00": 6, "t01": 9], last: 9)
        register.update(topics: topics(3), order: order)
        #expect(register.slot(for: "t00") == 6)
        #expect(register.slot(for: "t01") == 9)
        #expect(register.slot(for: "t02") == 0)
        // ungültiger Platz (Palette kleiner geworden) wird neu vergeben
        var odd = TopicColorRegister(slots: ["t00": 42], last: nil)
        odd.update(topics: topics(1), order: order)
        #expect(odd.slot(for: "t00") == 0)
    }

    @Test func fileRoundTripAndStates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paply-colors-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let url = dir.appendingPathComponent(TopicColorFile.fileName)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(TopicColorFile.load(from: url) == .missing)
        var register = TopicColorRegister()
        register.update(topics: topics(3), order: order)
        try TopicColorFile.save(register, to: url) // legt den Ordner an
        #expect(TopicColorFile.load(from: url) == .register(register))
        let before = try Data(contentsOf: url)
        try TopicColorFile.save(register, to: url)
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [TopicColorFile.fileName])
        try Data("{kaputt".utf8).write(to: url)
        #expect(TopicColorFile.load(from: url) == .damaged)
        try TopicColorFile.save(register, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        #expect(TopicColorFile.load(from: url) == .unreadable)
    }
}

@Suite("Oberfläche: Titel aus dem Rohtext")
struct RawTitleTests {
    @Test func dropsLeadingFillersAndCapitalizes() {
        let parts = RawTitle.split("Ähm, also am wochenende die tomaten ausgeizen und die beete gießen, sonst wird es zu trocken.")
        #expect(parts?.title == "Am wochenende die tomaten ausgeizen und …")
        #expect(parts?.rest == "die beete gießen, sonst wird es zu trocken.")
    }

    @Test func stopsAtSentenceEnd() {
        let parts = RawTitle.split("Mietvertrag prüfen. Bevor ich unterschreibe, die Klausel lesen.")
        #expect(parts?.title == "Mietvertrag prüfen")
        #expect(parts?.rest == "Bevor ich unterschreibe, die Klausel lesen.")
        #expect(RawTitle.split("wirklich?")?.title == "Wirklich?")
    }

    @Test func shortTextIsTitleOnly() {
        #expect(RawTitle.split("  Milch kaufen  ") == RawTitle.Parts(title: "Milch kaufen", rest: ""))
        #expect(RawTitle.split("also") == RawTitle.Parts(title: "Also", rest: ""))
    }

    @Test func fillersOnlyGiveNothing() {
        #expect(RawTitle.split("ähm … äh, hm") == nil)
        #expect(RawTitle.split("   ") == nil)
    }

    @Test func particlesNeedCommaWhenTheyCarryMeaning() {
        #expect(RawTitle.split("So viele Ideen für den Garten")?.title == "So viele Ideen für den Garten")
        #expect(RawTitle.split("So, jetzt noch Porto buchen")?.title == "Jetzt noch Porto buchen")
        #expect(RawTitle.split("Okay ähm ja, Sparplan erhöhen")?.title == "Sparplan erhöhen")
    }

    @Test func innerHesitationsDisappear() {
        let parts = RawTitle.split("Die Retro äh am Freitag ansprechen")
        #expect(parts?.title == "Die Retro am Freitag ansprechen")
    }
}
