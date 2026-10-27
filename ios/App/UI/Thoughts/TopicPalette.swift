import os
import PaplyKit
import SwiftUI
import UIKit

// Themenfarben: zehn ruhige Töne, stabil aus der Themen-ID abgeleitet – kein Datenfeld, nichts zu
// speichern. Jede Farbe gibt es hell und dunkel; die Schriftfarbe („ink“) hält auf ihrem Hintergrund
// mindestens 4,5 : 1 (dunkel: auf einer Karte oben im Waldverlauf, hell: auf #F2F3EF).
//
// Zuordnung: Jede ID hat über einen festen Hash (FNV-1a) ihren Wunschplatz. Damit zwei Themen nicht
// dieselbe Farbe tragen, wählen die Themen in der Reihenfolge ihres Entstehens (älteste zuerst); ist der
// Wunschplatz schon vergeben, nimmt ein Thema den nächsten freien. Erst ab elf Themen wiederholen sich
// Farben. Ein Thema behält seine Farbe, solange kein älteres gelöscht wird; zusammengeführte Themen
// bleiben als Alias im Speicher und halten ihren Platz – so ändert ein Zusammenführen keine Farbe.
// `ThoughtsModel` meldet die Themen bei jeder Änderung (`register`); ohne Meldung gilt der Wunschplatz.
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

    private static let assigned = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])
    private static let tints: [TopicTint] = entries.indices.map { makeTint(entries[$0], slot: $0) }
    private static let neutralTint = makeTint(neutralEntry, slot: nil)

    /// Pseudo-Thema (ohne Thema, Sammelstellen der Oberfläche)
    static func isNeutral(_ topicID: String?) -> Bool {
        guard let topicID, !topicID.isEmpty else { return true }
        return topicID.hasPrefix("_")
    }

    /// Platz in der Palette (nil = neutral)
    static func slot(for topicID: String?) -> Int? {
        guard !isNeutral(topicID), let topicID else { return nil }
        if let slot = assigned.withLock({ $0[topicID] }) { return slot }
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

    /// Themen melden (alle gespeicherten, auch zusammengeführte). Älteste wählen zuerst.
    static func register(_ topics: [Topic]) {
        let ordered = topics.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        var result: [String: Int] = [:]
        var taken = Set<Int>()
        for topic in ordered {
            if taken.count == entries.count { taken.removeAll() } // ab elf Themen: neue Runde
            var slot = preferredSlot(topic.id)
            while taken.contains(slot) { slot = (slot + 1) % entries.count }
            taken.insert(slot)
            result[topic.id] = slot
        }
        let final = result
        assigned.withLock { if $0 != final { $0 = final } }
    }

    /// Wunschplatz aus der ID (FNV-1a, unabhängig vom Programmstart)
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

// MARK: - Themen-Kennung in Themenfarbe

/// Symbol eines Themas auf seiner Farbfläche (abgerundetes Quadrat). Ohne Thema: gestrichelter Kreis.
struct TopicTintBadge: View {
    let topicID: String?
    let icon: TopicIcon?
    var size: CGFloat = 30

    var body: some View {
        let tint = TopicPalette.tint(for: topicID)
        Group {
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
