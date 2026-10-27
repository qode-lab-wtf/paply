// Rendert das iOS-App-Icon (1024 × 1024, randlos, ohne Transparenz) aus der Marke „p-Kopf“.
// Aufruf (macOS, im ios/-Ordner):  swift scripts/make-app-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// Geometrie wie brand/mark.svg bzw. Shared/Core/Brand.swift (PaplyMarkGeometry).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func gradient(_ a: UInt32, _ b: UInt32) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(a), rgb(b)] as CFArray, locations: [0, 1])!
}

let head: CGPath = {
    let circle = CGPath(ellipseIn: CGRect(x: 256, y: 236, width: 428, height: 428), transform: nil)
    let stem = CGPath(roundedRect: CGRect(x: 256, y: 450, width: 156, height: 392), cornerWidth: 78, cornerHeight: 78, transform: nil)
    let eye = CGPath(ellipseIn: CGRect(x: 458, y: 348, width: 124, height: 124), transform: nil)
    return circle.union(stem).subtracting(eye)
}()

let beakOutline: CGPath = {
    let path = CGMutablePath()
    let steps = 180
    func point(_ cx: Double, _ cy: Double, _ r: Double, _ deg: Double) -> CGPoint {
        CGPoint(x: cx + r * cos(deg * .pi / 180), y: cy + r * sin(deg * .pi / 180))
    }
    let outerFrom = 143.638, outerTo = 57.788 + 360
    let innerFrom = -11.056, innerTo = -147.518
    path.move(to: point(650, 450, 150, outerFrom))
    for i in 1...steps { path.addLine(to: point(650, 450, 150, outerFrom + (outerTo - outerFrom) * Double(i) / Double(steps))) }
    for i in 1...steps { path.addLine(to: point(622, 598, 110, innerFrom + (innerTo - innerFrom) * Double(i) / Double(steps))) }
    path.closeSubpath()
    return path
}()
let beak = beakOutline.subtracting(CGPath(ellipseIn: CGRect(x: 240, y: 220, width: 460, height: 460), transform: nil))

let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
// SVG-Koordinaten (y nach unten)
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Hintergrund: Wald, oben etwas heller
ctx.drawLinearGradient(gradient(0x1A4A33, 0x0A1D15), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// Marke mittig, ~58 % der Höhe; viewBox 230 220 600 640
let viewBox = CGRect(x: 230, y: 220, width: 600, height: 640)
let scale = 600.0 / viewBox.height
ctx.saveGState()
ctx.translateBy(x: CGFloat(size) / 2 - viewBox.midX * scale + 18, y: CGFloat(size) / 2 - viewBox.midY * scale)
ctx.scaleBy(x: scale, y: scale)

ctx.saveGState()
ctx.addPath(beak)
ctx.clip()
let box = beakOutline.boundingBoxOfPath
ctx.drawLinearGradient(gradient(0xFFE066, 0xFFA51F), start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.minX + box.width / 2, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(head)
ctx.clip()
ctx.drawLinearGradient(gradient(0x7CF29A, 0x22B45F), start: CGPoint(x: 300, y: 236), end: CGPoint(x: 470, y: 842), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()
ctx.restoreGState()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: output)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("geschrieben: \(url.path)")
