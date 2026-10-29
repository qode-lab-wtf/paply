import SwiftUI

// Orb „Echo“ (KONZEPT §3.4, §4): p-Kopf im Orb, Klangwolke, Echo-Ringe, Aura in Mint-Gold.
// Die Werte stammen 1:1 aus der Desktop-Pille (`electron-menubar/src/apps/recording/RecordingPill.tsx`):
// Wolke A dreht 0,045°/ms und wächst um 0,5·Pegel, Wolke B −0,032°/ms und 0,36·Pegel; Glättung
// Anstieg 0,5, Abfall 0,14 je 60-Hz-Bild (hier auf die echte Bildrate umgerechnet); Echo-Ring bei
// Pegel > 0,58, frühestens alle 420 ms, höchstens 3 gleichzeitig, 1 → 1,62 in 760 ms.
// Der Pegel wird je Bild gelesen (Lock-Wert), nie beobachtet: keine SwiftUI-Invalidierung je Sample.

struct EchoOrb: View {
    enum Mode: Equatable {
        /// Start läuft (atmet, keine Wolke)
        case starting
        /// Aufnahme läuft, noch keine Sprache (atmet)
        case listening
        /// Sprache erkannt (Aura hell)
        case heard
        /// fertig: Häkchen
        case done
        /// Fehler: Ausrufezeichen
        case error
    }

    var size: CGFloat
    var mode: Mode
    var showsAura = true
    var primary: Color = ThoughtTint.mint
    var secondary: Color = ThoughtTint.gold
    var auraColors: [Color] = ThoughtTint.aura
    var level: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var engine = EchoEngine()
    @State private var breathe = false
    @State private var spin = false
    @State private var donePulse = 0

    private var live: Bool { mode == .listening || mode == .heard }

    var body: some View {
        ZStack {
            if showsAura { aura }
            if live { cloud }
            orb
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            breathe = true
            spin = true
        }
    }

    // MARK: Aura (weich, Mint-Gold, dreht langsam)

    private var aura: some View {
        Circle()
            .fill(AngularGradient(colors: auraColors, center: .center))
            .frame(width: size * 1.28, height: size * 1.28)
            .blur(radius: size * 0.17)
            .opacity(mode == .heard ? 0.42 : (mode == .done ? 0.3 : 0.15))
            .rotationEffect(.degrees(spin && !reduce ? 360 : 0))
            .animation(reduce ? nil : .linear(duration: 16).repeatForever(autoreverses: false), value: spin)
            .animation(PaplyMotion.smooth(reduce), value: mode)
            .allowsHitTesting(false)
    }

    // MARK: Klangwolke + Echo-Ringe (Canvas, je Bild)

    private var cloud: some View {
        TimelineView(.animation(minimumInterval: reduce ? 1 / 30 : nil)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { gc, canvasSize in
                engine.step(target: Double(level()), now: t, reduce: reduce)
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = size / 2
                let smooth = engine.smooth
                // weich und leuchtend statt deckend: Unschärfe + additive Mischung auf dem Waldgrün
                var cloud = gc
                cloud.addFilter(.blur(radius: max(1, size * 0.03)))
                cloud.blendMode = .plusLighter

                // Wolke B (hinten, Gold), dann A (vorn, Mint)
                let scaleA = reduce ? 1 + smooth * 0.18 : 1 + smooth * 0.5
                let scaleB = reduce ? 1 : 1 + smooth * 0.36
                let rotA = reduce ? 0 : (t * 0.045).truncatingRemainder(dividingBy: 360)
                let rotB = reduce ? 0 : (-t * 0.032).truncatingRemainder(dividingBy: 360)
                drawBlob(EchoEngine.blobB, in: &cloud, center: center, radius: radius, scale: scaleB, degrees: rotB,
                         color: secondary.opacity(0.1 + smooth * 0.12))
                drawBlob(EchoEngine.blobA, in: &cloud, center: center, radius: radius, scale: scaleA, degrees: rotA,
                         color: primary.opacity(0.13 + smooth * 0.15))

                // Echo-Ringe
                for start in engine.rings {
                    let p = min(max((t - start) / 760, 0), 1)
                    let e = EchoEngine.ease(p)
                    let r = radius * (1 + 0.62 * e)
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    gc.stroke(Path(ellipseIn: rect), with: .color(primary.opacity(0.7 * (1 - e))),
                              lineWidth: max(1.25, size / 110))
                }
            }
        }
        .frame(width: size * 1.75, height: size * 1.75)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func drawBlob(_ unit: Path, in gc: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                          scale: Double, degrees: Double, color: Color) {
        var g = gc
        g.translateBy(x: center.x, y: center.y)
        g.rotate(by: .degrees(degrees))
        g.scaleBy(x: radius * scale, y: radius * scale)
        g.fill(unit, with: .color(color))
    }

    // MARK: Orb mit p-Kopf

    private var orb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.17), Color.white.opacity(0.03)],
                                     center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: size * 0.62))
                .background(Circle().fill(Color.paplyForest))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: max(0.75, size / 220)))
                .shadow(color: .black.opacity(size > 60 ? 0.5 : 0.25), radius: size * 0.12, y: size * 0.08)
            glyph
        }
        .frame(width: size, height: size)
        .scaleEffect(breatheScale)
        .animation(breatheAnimation, value: breathe)
        .keyframeAnimator(initialValue: 1.0, trigger: donePulse) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            // Puls 1 → 1,06 → 1 in 380 ms
            CubicKeyframe(1.06, duration: 0.15)
            SpringKeyframe(1.0, duration: 0.23)
        }
        .onChange(of: mode) { _, new in
            if new == .done, !reduce { donePulse += 1 }
        }
    }

    /// Atmen 1 ↔ 1,03 (2,4 s) vor der ersten Sprache
    private var breatheScale: CGFloat {
        guard !reduce, mode == .starting || mode == .listening else { return 1 }
        return breathe ? 1.03 : 1
    }

    private var breatheAnimation: Animation? {
        guard !reduce, mode == .starting || mode == .listening else { return PaplyMotion.smooth(reduce) }
        return .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    }

    @ViewBuilder
    private var glyph: some View {
        ZStack {
            switch mode {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Color.paplyGreenBright)
                    .transition(reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Color.paplyBeak)
                    .transition(reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            default:
                PaplyMark()
                    .frame(width: size * 0.4, height: size * 0.43)
                    .offset(x: -size * 0.01)
                    .transition(reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(reduce ? .linear(duration: 0.15) : .interpolatingSpring(stiffness: 520, damping: 24), value: mode)
    }
}

/// Glättung, Ringe und Formen der Klangwolke (Referenztyp: wird im Canvas je Bild fortgeschrieben).
final class EchoEngine {
    private(set) var smooth: Double = 0
    private(set) var rings: [Double] = []
    private var lastT: Double?
    private var lastRipple: Double = -10_000

    func step(target: Double, now t: Double, reduce: Bool) {
        let target = min(max(target, 0), 1)
        let dt = lastT.map { min(max(t - $0, 0), 100) } ?? 16.67
        guard dt > 0 || lastT == nil else { return }
        lastT = t
        // Faktoren der Pille gelten je 60-Hz-Bild → auf die echte Bildzeit umrechnen
        let k = target > smooth ? 0.5 : 0.14
        let a = 1 - pow(1 - k, dt / 16.67)
        smooth += (target - smooth) * a
        rings.removeAll { t - $0 > 760 }
        if !reduce, smooth > 0.58, t - lastRipple > 420, rings.count < 3 {
            lastRipple = t
            rings.append(t)
        }
    }

    /// Unregelmäßige Wolke um (0,0) mit Radius ≈ 1 (Form wie `blobPath(seed)` der Pille), hier als
    /// glatte Kurve (Catmull-Rom), damit sie auch bei 220 pt keine Ecken zeigt.
    static func blob(seed: Double) -> Path {
        let n = 48
        let points: [CGPoint] = (0..<n).map { i in
            let a = Double(i) / Double(n) * .pi * 2
            let r = 1 + 0.09 * sin(3 * a + seed) + 0.05 * sin(5 * a + seed * 2.1) + 0.03 * sin(7 * a)
            return CGPoint(x: cos(a) * r, y: sin(a) * r)
        }
        var path = Path()
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    static let blobA = blob(seed: 0.4)
    static let blobB = blob(seed: 2.2)

    /// `cubic-bezier(.2,.7,.3,1)` – x → y (Newton-Verfahren)
    static func ease(_ x: Double) -> Double {
        let p1x = 0.2, p1y = 0.7, p2x = 0.3, p2y = 1.0
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1x + 3 * (1 - t) * t * t * p2x + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1y + 3 * (1 - t) * t * t * p2y + t * t * t }
        func dbx(_ t: Double) -> Double {
            3 * (1 - t) * (1 - t) * p1x + 6 * (1 - t) * t * (p2x - p1x) + 3 * t * t * (1 - p2x)
        }
        var t = x
        for _ in 0..<6 {
            let d = dbx(t)
            guard abs(d) > 1e-6 else { break }
            t -= (bx(t) - x) / d
            t = min(max(t, 0), 1)
        }
        return by(t)
    }
}
