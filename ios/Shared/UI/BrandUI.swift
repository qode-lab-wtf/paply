import SwiftUI

extension Color {
    static let paplyGreen = Color(uiColor: Brand.green)
    static let paplyGreenBright = Color(uiColor: Brand.greenBright)
    static let paplyGreenDeep = Color(uiColor: Brand.greenDeep)
    static let paplyBeakDeep = Color(uiColor: PaplyMarkGeometry.beakColors.bottom)
    static let paplyForest = Color(uiColor: Brand.forest)
    static let paplyForestDeep = Color(uiColor: Brand.forestDeep)
    static let paplyBeak = Color(uiColor: Brand.beak)
    static let paplyText = Color(uiColor: Brand.text)
    static let paplyMicDot = Color(uiColor: Brand.micDot)
    static let paplyDanger = Color(uiColor: Brand.danger)
    static let paplyRecordTop = Color(uiColor: Brand.recordTop)
    static let paplyRecordBottom = Color(uiColor: Brand.recordBottom)
    static let paplyRecordInk = Color(uiColor: Brand.recordInk)
}

extension Animation {
    /// Feder „BOUNCY“ der Desktop-Pille
    static let paplyBouncy = Animation.interpolatingSpring(mass: 1, stiffness: Brand.Spring.bouncy.stiffness, damping: Brand.Spring.bouncy.damping)
    /// Feder „SMOOTH“ der Desktop-Pille
    static let paplySmooth = Animation.interpolatingSpring(mass: 1, stiffness: Brand.Spring.smooth.stiffness, damping: Brand.Spring.smooth.damping)
}

/// Ein Teil der Marke als Shape (seitenverhältnistreu in das Rechteck eingepasst).
struct PaplyMarkPart: Shape {
    enum Part {
        case head
        case beak
    }

    var part: Part

    func path(in rect: CGRect) -> Path {
        let source = part == .head ? PaplyMarkGeometry.head : PaplyMarkGeometry.beak
        return Path(source).applying(PaplyMarkGeometry.transform(fitting: rect))
    }
}

/// Die Marke „p-Kopf“ mit Verläufen, nur aus Shapes (kein Canvas, kein Asset) –
/// so zeichnet sie auch die Live Activity zuverlässig.
/// `monochrome` färbt alles in eine Farbe (z. B. auf Grün).
struct PaplyMark: View {
    var monochrome: Color?

    var body: some View {
        ZStack {
            if let monochrome {
                PaplyMarkPart(part: .beak).fill(monochrome)
                PaplyMarkPart(part: .head).fill(monochrome)
            } else {
                PaplyMarkPart(part: .beak).fill(LinearGradient(
                    colors: [Color(uiColor: PaplyMarkGeometry.beakColors.top), Color(uiColor: PaplyMarkGeometry.beakColors.bottom)],
                    startPoint: Self.unit(PaplyMarkGeometry.beakGradient.start),
                    endPoint: Self.unit(PaplyMarkGeometry.beakGradient.end)
                ))
                PaplyMarkPart(part: .head).fill(LinearGradient(
                    colors: [Color(uiColor: PaplyMarkGeometry.headColors.top), Color(uiColor: PaplyMarkGeometry.headColors.bottom)],
                    startPoint: Self.unit(PaplyMarkGeometry.headGradient.start),
                    endPoint: Self.unit(PaplyMarkGeometry.headGradient.end)
                ))
            }
        }
        .aspectRatio(PaplyMarkGeometry.viewBox.width / PaplyMarkGeometry.viewBox.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// viewBox-Punkt → UnitPoint (die Ansicht hat genau das Seitenverhältnis der viewBox)
    private static func unit(_ point: CGPoint) -> UnitPoint {
        let box = PaplyMarkGeometry.viewBox
        return UnitPoint(x: (point.x - box.minX) / box.width, y: (point.y - box.minY) / box.height)
    }
}
