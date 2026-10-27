import SwiftUI
import UIKit

// Farben der Karte, hell und dunkel. Themenfarben kommen aus `TopicPalette` (stabil aus der ID).
// Dunkel wie der Entwurf: Kreise leuchten aus dem Waldgrün. Hell: pastellige Kugeln auf warmem Weiß.

struct MapStyle {
    let dark: Bool

    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
    }

    // MARK: Fläche und Schrift

    /// Grundton (auch der Ring, der Punkte von Linien trennt)
    var ground: Color { dark ? .paplyForest : Color(uiColor: UIColor(hex: 0xF2F3EF)) }
    var ink: Color { dark ? .paplyText : Color(uiColor: UIColor(hex: 0x0F1511)) }
    var secondary: Color { dark ? Color.paplyText.opacity(0.62) : Color(uiColor: UIColor(hex: 0x2B342F)).opacity(0.64) }
    var tertiary: Color { dark ? Color.paplyText.opacity(0.4) : Color(uiColor: UIColor(hex: 0x2B342F)).opacity(0.42) }
    /// offene Aufgabe (Ring um den Punkt), wie das Gold der Gedanken
    var open: Color { dark ? ThoughtTint.gold : Color(uiColor: UIColor(hex: 0xC98A12)) }
    /// „Ohne Thema“ und Sammelkreis: neutraler Ring, zarte Fläche, kleine Kreise im Sammelkreis
    var neutralRing: Color { dark ? Color.paplyText.opacity(0.44) : Color(uiColor: UIColor(hex: 0x2B342F)).opacity(0.42) }
    var neutralFill: Color { dark ? Color.white.opacity(0.04) : Color(uiColor: UIColor(hex: 0x2B342F)).opacity(0.04) }
    var neutralGlyph: Color { dark ? Color.paplyText.opacity(0.42) : Color(uiColor: UIColor(hex: 0x2B342F)).opacity(0.36) }

    @ViewBuilder
    var background: some View {
        if dark {
            PaplyBackground()
        } else {
            ZStack {
                Color(uiColor: UIColor(hex: 0xF2F3EF))
                RadialGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.52),
                               startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Themen

    struct Bubble {
        /// Leuchten um den Kreis
        var glow: Color
        var glowStrength: Double
        /// Verlauf im Kreis: Lichtpunkt oben links → Rand
        var body: [Gradient.Stop]
        var rim: Color
        var glyph: Color
        /// Punkte und Linien
        var dot: Color
        var line: Color
    }

    func bubble(_ topicID: String) -> Bubble {
        let tint = TopicPalette.tint(for: topicID)
        if dark {
            return Bubble(glow: tint.base, glowStrength: 0.46,
                          body: [.init(color: tint.light, location: 0), .init(color: tint.base, location: 0.52),
                                 .init(color: tint.deep, location: 1)],
                          rim: Color.white.opacity(0.16), glyph: Color.white.opacity(0.96),
                          dot: tint.light.mix(with: tint.base, by: 0.45), line: tint.base)
        }
        return Bubble(glow: tint.base, glowStrength: 0.2,
                      body: [.init(color: Color.white.mix(with: tint.light, by: 0.08), location: 0),
                             .init(color: Color.white.mix(with: tint.light, by: 0.5), location: 0.55),
                             .init(color: tint.light, location: 1)],
                      rim: tint.deep.opacity(0.2), glyph: tint.ink, dot: tint.base, line: tint.base)
    }

    // MARK: Punktraster

    /// Kachel mit einem Punkt in der Mitte; gekachelt und mit der Kamera skaliert gezeichnet.
    static let gridTile: CGFloat = 24

    @MainActor
    func gridImage() -> Image {
        dark ? Self.darkGrid : Self.lightGrid
    }

    @MainActor private static let darkGrid = makeGrid(UIColor.white.withAlphaComponent(0.075))
    @MainActor private static let lightGrid = makeGrid(UIColor(red: 16 / 255, green: 40 / 255, blue: 26 / 255, alpha: 0.11))

    @MainActor
    private static func makeGrid(_ color: UIColor) -> Image {
        let size = CGSize(width: gridTile, height: gridTile)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: gridTile / 2 - 0.9, y: gridTile / 2 - 0.9, width: 1.8, height: 1.8))
        }
        return Image(uiImage: image)
    }
}
