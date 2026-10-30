import PaplyKit
import SwiftUI
import UIKit

// Bild statt Symbol (TopicImages): überall, wo das Themen-Symbol steht, erscheint – falls gewählt – das Bild,
// in derselben Form (abgerundetes Quadrat bei Kennungen, Kreis im Fließtext) mit feinem Rand in der Themenfarbe.
// Ohne Bild bleibt das Symbol.

/// Themenbild in Form gebracht: abgerundetes Quadrat (`cornerRatio`) oder Kreis, feiner Rand in der Themenfarbe.
struct TopicImageTile: View {
    let image: UIImage
    let topicID: String?
    let size: CGFloat
    /// Eckenradius im Verhältnis zur Kante (wie die Symbol-Kennung); nil = Kreis
    var cornerRatio: CGFloat? = 0.3

    var body: some View {
        let tint = TopicPalette.tint(for: topicID)
        let line: CGFloat = size >= 36 ? 1.5 : 1
        let picture = Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
        Group {
            if let cornerRatio {
                let shape = RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                picture
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(tint.base.opacity(0.95), lineWidth: line))
            } else {
                picture
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(tint.base.opacity(0.95), lineWidth: line))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Themen-Kennung im Fließtext (Zeilen, Pillen): das Bild als kleiner Kreis, sonst das Symbol. Folgt Dynamic Type
/// wie das Symbol; die Farbe des Symbols kommt von außen (`foregroundStyle`).
struct TopicMark: View {
    let topicID: String?
    let icon: TopicIcon?
    var size: CGFloat = 15
    var stroke: CGFloat = 1.9
    var relativeTo: Font.TextStyle = .body
    /// Kante des Bilds im Verhältnis zum Symbol (ein Kreis wirkt bei gleicher Kante kleiner)
    var imageScale: CGFloat = 1.2

    @ScaledMetric private var scale: CGFloat

    init(topicID: String?, icon: TopicIcon?, size: CGFloat = 15, stroke: CGFloat = 1.9,
         relativeTo: Font.TextStyle = .body, imageScale: CGFloat = 1.2) {
        self.topicID = topicID
        self.icon = icon
        self.size = size
        self.stroke = stroke
        self.relativeTo = relativeTo
        self.imageScale = imageScale
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: relativeTo)
    }

    var body: some View {
        if let image = TopicImages.shared.image(for: topicID) {
            TopicImageTile(image: image, topicID: topicID, size: size * imageScale * min(scale, 2.4), cornerRatio: nil)
                .accessibilityHidden(true)
        } else if let icon {
            TopicGlyph(key: icon.rawValue, size: size, stroke: stroke, relativeTo: relativeTo)
        }
    }
}
