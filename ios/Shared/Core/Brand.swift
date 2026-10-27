import CoreGraphics
import UIKit

/// Markenfarben aus `electron-menubar/src/globals.css` und der Marke „p-Kopf“.
enum Brand {
    static let green = UIColor(hex: 0x22B45F)
    static let greenBright = UIColor(hex: 0x3AD879)
    static let greenDeep = UIColor(hex: 0x13803F)
    static let forest = UIColor(hex: 0x0F2C20)
    static let forestDeep = UIColor(hex: 0x0A1D15)
    static let beak = UIColor(hex: 0xFFC233)
    static let mint = UIColor(hex: 0xE8F8EE)
    static let text = UIColor(hex: 0xEEF5F0)
    /// Aufnahme-Fläche (Verlauf oben → unten) und Schrift darauf
    static let recordTop = UIColor(hex: 0x45E086)
    static let recordBottom = UIColor(hex: 0x22B45F)
    static let recordInk = UIColor(hex: 0x05210F)
    static let micDot = UIColor(hex: 0xFF9F0A)
    static let danger = UIColor(hex: 0xFF6B5E)

    /// Feder wie die Desktop-Pille (RecordingPill.tsx): BOUNCY k=520 c=24, SMOOTH k=420 c=30, Masse 1.
    enum Spring {
        static let bouncy = (stiffness: 520.0, damping: 24.0)
        static let smooth = (stiffness: 420.0, damping: 30.0)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Die Marke „p-Kopf“ als Pfade (aus `brand/mark.svg`, viewBox 230 220 600 640).
enum PaplyMarkGeometry {
    static let viewBox = CGRect(x: 230, y: 220, width: 600, height: 640)

    // CGPath ist unveränderlich – gemeinsame Nutzung über Threads ist sicher.

    /// Kopf (Kreis + Stiel) ohne Auge
    nonisolated(unsafe) static let head: CGPath = {
        let circle = CGPath(ellipseIn: CGRect(x: 256, y: 236, width: 428, height: 428), transform: nil)
        let stem = CGPath(roundedRect: CGRect(x: 256, y: 450, width: 156, height: 392), cornerWidth: 78, cornerHeight: 78, transform: nil)
        let eye = CGPath(ellipseIn: CGRect(x: 458, y: 348, width: 124, height: 124), transform: nil)
        return circle.union(stem).subtracting(eye)
    }()

    /// Schnabel, mit Abstand zum Kopf ausgeschnitten
    nonisolated(unsafe) static let beak: CGPath = {
        let gap = CGPath(ellipseIn: CGRect(x: 240, y: 220, width: 460, height: 460), transform: nil)
        return beakOutline.subtracting(gap)
    }()

    /// Schnabel vor dem Ausschneiden (für den Verlauf: objectBoundingBox)
    nonisolated(unsafe) static let beakOutline: CGPath = {
        // Bögen aus dem SVG: r=150 um (650, 450) und r=110 um (622, 598)
        let path = CGMutablePath()
        let steps = 72
        func point(_ cx: Double, _ cy: Double, _ r: Double, _ deg: Double) -> CGPoint {
            CGPoint(x: cx + r * cos(deg * .pi / 180), y: cy + r * sin(deg * .pi / 180))
        }
        let outerFrom = 143.638, outerTo = 57.788 + 360
        let innerFrom = -11.056, innerTo = -147.518
        path.move(to: point(650, 450, 150, outerFrom))
        for i in 1...steps {
            path.addLine(to: point(650, 450, 150, outerFrom + (outerTo - outerFrom) * Double(i) / Double(steps)))
        }
        for i in 1...steps {
            path.addLine(to: point(622, 598, 110, innerFrom + (innerTo - innerFrom) * Double(i) / Double(steps)))
        }
        path.closeSubpath()
        return path
    }()

    /// Verläufe in viewBox-Koordinaten
    static let headGradient = (start: CGPoint(x: 300, y: 236), end: CGPoint(x: 470, y: 842))
    static var beakGradient: (start: CGPoint, end: CGPoint) {
        let box = beakOutline.boundingBoxOfPath
        return (CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX + box.width * 0.5, y: box.maxY))
    }

    static let headColors = (top: UIColor(hex: 0x7CF29A), bottom: UIColor(hex: 0x22B45F))
    static let beakColors = (top: UIColor(hex: 0xFFE066), bottom: UIColor(hex: 0xFFA51F))

    /// Transform von viewBox in ein Zielrechteck (Seitenverhältnis bleibt, zentriert).
    static func transform(fitting rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.midX - viewBox.midX * scale
        let dy = rect.midY - viewBox.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)
    }
}
