// Erzeugt die eigenen SF-Symbole „paply.mark“ und „paply.mark.fill“ (p-Kopf) für das Steuerelement
// „Gedanke“ – im Format der SF-Symbols-Vorlage (Template v.3.0, statisch: Ultralight-S, Regular-S,
// Black-S mit Rand- und Grundlinien). Geometrie wie brand/mark.svg bzw. PaplyMarkGeometry.
// Aufruf (macOS, im ios/-Ordner):  swift scripts/make-control-symbol.swift Widgets/Assets.xcassets
import CoreGraphics
import Foundation

let catalog = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Widgets/Assets.xcassets"

// MARK: Marke (viewBox 230 220 600 640)

let head: CGPath = {
    let circle = CGPath(ellipseIn: CGRect(x: 256, y: 236, width: 428, height: 428), transform: nil)
    let stem = CGPath(roundedRect: CGRect(x: 256, y: 450, width: 156, height: 392), cornerWidth: 78, cornerHeight: 78, transform: nil)
    let eye = CGPath(ellipseIn: CGRect(x: 458, y: 348, width: 124, height: 124), transform: nil)
    return circle.union(stem).subtracting(eye)
}()

let beak: CGPath = {
    let path = CGMutablePath()
    let steps = 72
    func point(_ cx: Double, _ cy: Double, _ r: Double, _ deg: Double) -> CGPoint {
        CGPoint(x: cx + r * cos(deg * .pi / 180), y: cy + r * sin(deg * .pi / 180))
    }
    let outerFrom = 143.638, outerTo = 57.788 + 360
    let innerFrom = -11.056, innerTo = -147.518
    path.move(to: point(650, 450, 150, outerFrom))
    for i in 1...steps { path.addLine(to: point(650, 450, 150, outerFrom + (outerTo - outerFrom) * Double(i) / Double(steps))) }
    for i in 1...steps { path.addLine(to: point(622, 598, 110, innerFrom + (innerTo - innerFrom) * Double(i) / Double(steps))) }
    path.closeSubpath()
    return path.subtracting(CGPath(ellipseIn: CGRect(x: 240, y: 220, width: 460, height: 460), transform: nil))
}()

let mark: CGPath = head.union(beak)

// MARK: Glyphen-Koordinaten (Punktgröße 100: Grundlinie y = 0, Versalhöhe ≈ -70,5)

/// Marke so skalieren, dass sie von y = -78 bis +6 reicht (wie hohe SF-Symbole), links 2 Einheiten Rand.
func placed(_ path: CGPath, height: Double, center: CGPoint? = nil) -> CGPath {
    let box = CGRect(x: 230, y: 220, width: 600, height: 640)
    let s = height / box.height
    var t = CGAffineTransform(translationX: -box.minX, y: -box.minY).concatenating(CGAffineTransform(scaleX: s, y: s))
    if let center {
        t = t.concatenating(CGAffineTransform(translationX: center.x - box.width * s / 2, y: center.y - box.height * s / 2))
    } else {
        t = t.concatenating(CGAffineTransform(translationX: 2, y: -78))
    }
    return path.copy(using: &t)!
}

let plain = placed(mark, height: 84)
let plainWidth = 84.0 * 600 / 640 + 4

let fillCircle = CGPath(ellipseIn: CGRect(x: 1, y: -78, width: 84, height: 84), transform: nil)
let fill = fillCircle.subtracting(placed(mark, height: 84 * 0.62, center: CGPoint(x: 43, y: -36)))
let fillWidth = 86.0

func svgPath(_ path: CGPath) -> String {
    var d = ""
    func f(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y))"
        case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y))"
        case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
        case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

// MARK: Vorlage

func template(name: String, path: CGPath, width: Double) -> String {
    let d = svgPath(path)
    // Spalten der Vorlage (Ultralight, Regular, Black) in der Zeile „Small“ (Grundlinie 696)
    let columns: [(String, Double)] = [("Ultralight-S", 515.0), ("Regular-S", 1405.0), ("Black-S", 2887.0)]
    let guide = "style=\"fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;\""
    let margin = "style=\"fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;\""
    var margins = ""
    var symbols = ""
    for (variant, x) in columns {
        margins += "  <line id=\"left-margin-\(variant)\" \(margin) x1=\"\(x)\" x2=\"\(x)\" y1=\"600.785\" y2=\"720.121\"/>\n"
        margins += "  <line id=\"right-margin-\(variant)\" \(margin) x1=\"\(x + width)\" x2=\"\(x + width)\" y1=\"600.785\" y2=\"720.121\"/>\n"
        symbols += "  <g id=\"\(variant)\" transform=\"matrix(1 0 0 1 \(x) 696)\">\n   <path d=\"\(d)\"/>\n  </g>\n"
    }
    let weights = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
    var weightLabels = ""
    for (i, w) in weights.enumerated() {
        let x = 559.711 + Double(i) * 296.711
        weightLabels += "  <text style=\"stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;\" transform=\"matrix(1 0 0 1 \(String(format: "%.3f", x)) 322)\">\(w)</text>\n"
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE svg
    PUBLIC "-//W3C//DTD SVG 1.1//EN"
           "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
     <!--glyph: "\(name)", point size: 100.0, template writer version: "65.1"-->
     <g id="Notes">
      <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
      <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
    \(weightLabels)  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1903" y2="1903"/>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 1953)">Design Variations</text>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 726)">Small</text>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1156)">Medium</text>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1586)">Large</text>
      <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
     </g>
     <g id="Guides">
      <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 696)">
       <path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.1206-26.7841L12.5493-26.7841ZM55.1724 0L57.7884 0L30.6205-70.459L29.0444-70.459L29.0444-67.1323Z"/>
      </g>
      <line id="Baseline-S" \(guide) x1="263" x2="3036" y1="696" y2="696"/>
      <line id="Capline-S" \(guide) x1="263" x2="3036" y1="625.541" y2="625.541"/>
      <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1126)">
       <path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.1206-26.7841L12.5493-26.7841ZM55.1724 0L57.7884 0L30.6205-70.459L29.0444-70.459L29.0444-67.1323Z"/>
      </g>
      <line id="Baseline-M" \(guide) x1="263" x2="3036" y1="1126" y2="1126"/>
      <line id="Capline-M" \(guide) x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
      <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1556)">
       <path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.1206-26.7841L12.5493-26.7841ZM55.1724 0L57.7884 0L30.6205-70.459L29.0444-70.459L29.0444-67.1323Z"/>
      </g>
      <line id="Baseline-L" \(guide) x1="263" x2="3036" y1="1556" y2="1556"/>
      <line id="Capline-L" \(guide) x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
    \(margins) </g>
     <g id="Symbols">
    \(symbols) </g>
    </svg>

    """
}

func write(name: String, path: CGPath, width: Double) throws {
    let dir = URL(fileURLWithPath: catalog).appendingPathComponent("\(name).symbolset")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try template(name: name, path: path, width: width).write(to: dir.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
    let contents = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "symbols" : [
        {
          "filename" : "\(name).svg",
          "idiom" : "universal"
        }
      ]
    }

    """
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("geschrieben: \(dir.path)")
}

let root = URL(fileURLWithPath: catalog)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let rootContents = "{\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
try rootContents.write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try write(name: "paply.mark", path: plain, width: plainWidth)
try write(name: "paply.mark.fill", path: fill, width: fillWidth)
