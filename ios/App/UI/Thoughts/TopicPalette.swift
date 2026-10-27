import os
import PaplyKit
import SwiftUI
import UIKit

// Themenfarben: zehn ruhige Töne. Jede Farbe gibt es hell und dunkel; die Schriftfarbe („ink“) hält auf
// ihrem Hintergrund mindestens 4,5 : 1 (dunkel: auf einer Karte oben im Waldverlauf, hell: auf #F2F3EF).
//
// Zuordnung (`TopicColorRegister` in PaplyKit): Ein Thema bekommt seinen Farbplatz einmal, bei der ersten
// Sichtung – den ersten freien in `assignmentOrder`, neue Themen in Anlagereihenfolge – und behält ihn. Es
// wird nie umverteilt. Zusammengeführte Themen belegen keinen Platz und zeigen die Farbe ihres Ziels; gelöschte
// geben ihren Platz frei. Ab elf Themen wiederholt sich eine Farbe, aber nie die zuletzt vergebene.
// Das Register liegt als `topic-colors.json` neben den Gedanken-Daten (`TopicColorStore`).
//
// Pseudo-Themen (nil, "", IDs mit „_“ am Anfang, z. B. „Ohne Thema“) bekommen den neutralen Ton.

/// Alle Töne eines Themas. Die Farben sind dynamisch (hell/dunkel folgt der Umgebung).
struct TopicTint: Sendable, Equatable {
    /// Platz in der Palette; nil = neutral (ohne Thema)
    let slot: Int?
    /// Symbol, Name, kleine Schrift (Kontrast ≥ 4,5 : 1)
    let ink: Color
    /// satter Mittelton: Kreise, Punkte, Balken
    let base: Color
    /// helle Seite des Mitteltons (Verlauf oben links in Kreisen)
    let light: Color
    /// dunkle Seite (Verlauf unten rechts, Schatten)
    let deep: Color
    /// zarte Fläche (Themen-Feld, Kopf des Panels)
    let fill: Color
    /// Fläche hinter dem Symbol
    let badge: Color
    /// feine Kante um Flächen
    let stroke: Color
}

enum TopicPalette {
    /// Ton, Sättigung, Helligkeit der Schrift dunkel / hell (für 4,5 : 1 ausgemessen)
    private struct Entry {
        let name: String
        let hue: CGFloat
        let saturation: CGFloat
        let inkDark: CGFloat
        let inkLight: CGFloat
    }

    private static let entries: [Entry] = [
        Entry(name: "Blau", hue: 214, saturation: 0.72, inkDark: 0.79, inkLight: 0.44),
        Entry(name: "Indigo", hue: 240, saturation: 0.56, inkDark: 0.84, inkLight: 0.48),
        Entry(name: "Violett", hue: 272, saturation: 0.48, inkDark: 0.82, inkLight: 0.46),
        Entry(name: "Rosé", hue: 334, saturation: 0.58, inkDark: 0.81, inkLight: 0.44),
        Entry(name: "Koralle", hue: 6, saturation: 0.72, inkDark: 0.81, inkLight: 0.44),
        Entry(name: "Orange", hue: 28, saturation: 0.86, inkDark: 0.75, inkLight: 0.34),
        Entry(name: "Gold", hue: 44, saturation: 0.84, inkDark: 0.75, inkLight: 0.28),
        Entry(name: "Mint", hue: 164, saturation: 0.50, inkDark: 0.75, inkLight: 0.30),
        Entry(name: "Türkis", hue: 192, saturation: 0.64, inkDark: 0.75, inkLight: 0.31),
        Entry(name: "Sand", hue: 26, saturation: 0.34, inkDark: 0.77, inkLight: 0.39),
    ]

    private static let neutralEntry = Entry(name: "Neutral", hue: 150, saturation: 0.08, inkDark: 0.76, inkLight: 0.39)

    /// Anzahl der Farben
    static var count: Int { entries.count }

    /// Name der Farbe (Entwicklerbereich, Tests)
    static func name(of slot: Int?) -> String {
        guard let slot, entries.indices.contains(slot) else { return neutralEntry.name }
        return entries[slot].name
    }

    // MARK: Zuordnung

    /// Vergabe-Reihenfolge: nacheinander vergebene Plätze liegen im Farbkreis weit auseinander
    /// (Blau, Gold, Rosé, Mint, Violett, Koralle, Türkis, Orange, Indigo, Sand).
    static let assignmentOrder = [0, 6, 3, 7, 2, 4, 8, 5, 1, 9]

    /// Stand des Registers zum Lesen von überall (Karte zeichnet auch außerhalb des Hauptakteurs)
    fileprivate static let current = OSAllocatedUnfairLock<TopicColorRegister>(initialState: TopicColorRegister())
    private static let tints: [TopicTint] = entries.indices.map { makeTint(entries[$0], slot: $0) }
    private static let neutralTint = makeTint(neutralEntry, slot: nil)

    /// Pseudo-Thema (ohne Thema, Sammelstellen der Oberfläche)
    static func isNeutral(_ topicID: String?) -> Bool {
        guard let topicID, !topicID.isEmpty else { return true }
        return topicID.hasPrefix("_")
    }

    /// Platz in der Palette (nil = neutral). Aliasse zeigen die Farbe ihres Ziels. Ein Thema, das das Modell
    /// noch nicht gemeldet hat, bekommt vorläufig seinen Wunschplatz aus der ID (wird nicht gespeichert).
    static func slot(for topicID: String?) -> Int? {
        guard !isNeutral(topicID), let topicID else { return nil }
        if let slot = current.withLock({ $0.slot(for: topicID) }), entries.indices.contains(slot) { return slot }
        return preferredSlot(topicID)
    }

    /// Alle Töne eines Themas (dynamisch hell/dunkel)
    static func tint(for topicID: String?) -> TopicTint {
        guard let slot = slot(for: topicID) else { return neutralTint }
        return tints[slot]
    }

    /// Akzentfarbe eines Themas (Symbol, Name) für ein festes Farbschema
    static func color(for topicID: String?, scheme: ColorScheme) -> Color {
        let entry = slot(for: topicID).map { entries[$0] } ?? neutralEntry
        return Color(uiColor: hsl(entry, scheme == .dark ? entry.inkDark : entry.inkLight))
    }

    /// Satter Mittelton eines Themas (Kreise, Punkte) für ein festes Farbschema
    static func baseColor(for topicID: String?, scheme: ColorScheme) -> Color {
        let entry = slot(for: topicID).map { entries[$0] } ?? neutralEntry
        return Color(uiColor: hsl(entry, scheme == .dark ? 0.6 : 0.52))
    }

    /// Themen melden (alle gespeicherten, auch zusammengeführte). `persistent`: Meldung des angebundenen
    /// Modells (`ThoughtsModel.shared`). Beispieldaten im Debug haben ein eigenes Register nur im Speicher –
    /// so stört keines das andere (siehe `TopicColorStore`).
    @MainActor
    static func register(_ topics: [Topic], persistent: Bool = false) {
        TopicColorStore.shared.register(topics, persistent: persistent)
    }

    /// Wunschplatz aus der ID (FNV-1a, unabhängig vom Programmstart) – nur vorläufig, s. `slot(for:)`
    static func preferredSlot(_ id: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(entries.count))
    }

    // MARK: Farben

    private static func makeTint(_ e: Entry, slot: Int?) -> TopicTint {
        TopicTint(
            slot: slot,
            ink: dynamic(dark: hsl(e, e.inkDark), light: hsl(e, e.inkLight)),
            base: dynamic(dark: hsl(e, 0.6), light: hsl(e, 0.52)),
            light: dynamic(dark: hsl(e, 0.8), light: hsl(e, 0.72)),
            deep: dynamic(dark: hsl(e, 0.36), light: hsl(e, 0.36)),
            fill: dynamic(dark: hsl(e, 0.6, alpha: 0.10), light: hsl(e, 0.45, alpha: 0.08)),
            badge: dynamic(dark: hsl(e, 0.6, alpha: 0.22), light: hsl(e, 0.5, alpha: 0.14)),
            stroke: dynamic(dark: hsl(e, 0.7, alpha: 0.16), light: hsl(e, 0.35, alpha: 0.14))
        )
    }

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// HSL → UIColor (die Palette ist in HSL gedacht, wie im Entwurf)
    private static func hsl(_ e: Entry, _ lightness: CGFloat, alpha: CGFloat = 1) -> UIColor {
        let s = e.saturation, l = lightness
        let brightness = l + s * min(l, 1 - l)
        let saturation = brightness == 0 ? 0 : 2 * (1 - l / brightness)
        return UIColor(hue: e.hue / 360, saturation: saturation, brightness: brightness, alpha: alpha)
    }
}

// MARK: - Register auf der Platte

/// Farbplätze der Themen: `topic-colors.json` neben den Gedanken-Daten (`ThoughtsEnvironment.root`, wie
/// `map-anchors.json`) – gleicher Dateischutz, geht mit den Gedanken weg. Geschrieben wird atomar und der Reihe
/// nach, sobald sich ein Platz ändert.
///
/// Sicherheit:
/// - Vor dem ersten Entsperren wird weder gelesen noch geschrieben (`ProtectedData`); Meldungen aus dieser Zeit
///   werden danach nachgeholt. Ist die Datei da, aber nicht lesbar, wird nie geschrieben – sonst gingen alle
///   Plätze verloren. Erneut gelesen wird frühestens nach 5 s.
/// - Beispieldaten (`-PaplyPreviewData`, `-PaplyMany`, `-PaplyCount`, `-PaplyEmpty`) und SwiftUI-Vorschauen nutzen
///   ein Register nur im Speicher und nehmen nur Meldungen der Beispielmodelle an; das angebundene Modell lädt
///   im Debug trotzdem im Hintergrund, seine Meldungen fallen dann weg. Umgekehrt ändern Beispielmodelle nie
///   die Datei.
@MainActor
final class TopicColorStore {
    static let shared = TopicColorStore(url: storageURL)

    private enum Phase {
        case notLoaded
        case loaded
        case blocked(since: Date)
    }

    /// nil = nur im Speicher
    private let url: URL?
    private var phase: Phase = .notLoaded
    private var register = TopicColorRegister()
    /// letzte Meldung, solange nicht geladen (wird nachgeholt)
    private var latest: [Topic]?
    private var waitsForUnlock = false
    private var writes: Task<Void, Never>?

    init(url: URL?) {
        self.url = url
        if url == nil { phase = .loaded }
    }

    private static var storageURL: URL? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        #if DEBUG
        if ThoughtsDebug.previewData || ProcessInfo.processInfo.arguments.contains("-PaplyEmpty") { return nil }
        #endif
        return ThoughtsEnvironment.root.appendingPathComponent(TopicColorFile.fileName)
    }

    func register(_ topics: [Topic], persistent: Bool) {
        // Datei-Register nimmt nur das angebundene Modell an, das Speicher-Register nur Beispielmodelle
        guard persistent == (url != nil) else { return }
        latest = topics
        guard loadIfNeeded() else { return }
        latest = nil
        apply(topics)
    }

    private func apply(_ topics: [Topic]) {
        let changed = register.update(topics: topics, order: TopicPalette.assignmentOrder)
        let snapshot = register
        TopicPalette.current.withLock { $0 = snapshot }
        if changed { save() }
    }

    /// true = geladen (Datei gelesen, fehlt oder kaputt); false = noch nicht lesbar
    private func loadIfNeeded() -> Bool {
        switch phase {
        case .loaded:
            return true
        case .blocked(let since) where Date().timeIntervalSince(since) < 5:
            return false
        default:
            break
        }
        guard let url else {
            phase = .loaded
            return true
        }
        guard ProtectedData.isReadable else {
            if !waitsForUnlock {
                waitsForUnlock = true
                ProtectedData.whenReadable { [weak self] _ in self?.resumeAfterUnlock() }
            }
            return false
        }
        switch TopicColorFile.load(from: url) {
        case .register(let stored):
            register = stored
            phase = .loaded
        case .missing, .damaged:
            register = TopicColorRegister()
            phase = .loaded
        case .unreadable:
            phase = .blocked(since: Date())
            Diag.log("topic.colors.unreadable", [:])
            return false
        }
        return true
    }

    private func resumeAfterUnlock() {
        waitsForUnlock = false
        guard let latest, loadIfNeeded() else { return }
        self.latest = nil
        apply(latest)
    }

    private func save() {
        guard let url, case .loaded = phase, ProtectedData.isReadable else { return }
        let snapshot = register
        let previous = writes
        writes = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try TopicColorFile.save(snapshot, to: url)
            } catch {
                Diag.log("topic.colors.write.failed", ["error": .s(String(describing: type(of: error)))])
            }
        }
    }
}

// MARK: - Themen-Kennung in Themenfarbe

/// Symbol eines Themas auf seiner Farbfläche (abgerundetes Quadrat). Hat das Thema ein Bild (`TopicImages`), steht
/// das Bild im gleichen Quadrat, mit feinem Rand in der Themenfarbe. Ohne Thema: gestrichelter Kreis.
struct TopicTintBadge: View {
    let topicID: String?
    let icon: TopicIcon?
    var size: CGFloat = 30

    var body: some View {
        if let image = TopicImages.shared.image(for: topicID) {
            TopicImageTile(image: image, topicID: topicID, size: size, cornerRatio: 0.3)
                .accessibilityHidden(true)
        } else {
            symbol
        }
    }

    private var symbol: some View {
        let tint = TopicPalette.tint(for: topicID)
        return Group {
            if let icon {
                TopicGlyph(key: icon.rawValue, size: size * 0.54, stroke: size > 40 ? 1.8 : 2, scales: false)
            } else {
                LucideImage(.circleDashed, size: size * 0.54, stroke: 2, scales: false)
            }
        }
        .foregroundStyle(tint.ink)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(tint.badge))
        .accessibilityHidden(true)
    }
}
