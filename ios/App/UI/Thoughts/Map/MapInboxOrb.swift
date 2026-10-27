import PaplyKit
import SwiftUI

// Eingang der Karte: eine kleine, lebendige Kugel in Paply-Grün an fester Stelle (unten mittig, ohne Anker), darin
// die Zahl der Gedanken, die Paply gerade ordnet oder die warten; darunter klein, was passiert. Solange etwas
// geordnet wird, atmet sie und ein Lichtschimmer läuft über ihren Rand. Warten alle (Netz, Schlüssel …), ruht sie
// gedämpft. Bei jedem Abflug eines fertigen Gedankens stößt sie kurz nach. Antippen öffnet „Noch nicht geordnet“.
//
// Atmen und Schimmer gibt es nur, solange geordnet wird: Beide stecken in einem eigenen Zweig, der bei jedem Wechsel
// zu „Wird geordnet …“ neu beginnt und beim Warten ganz verschwindet – dann läuft nichts (auch nicht unsichtbar).

struct MapInboxOrb: View {
    let count: Int
    let status: MapInboxStatus
    /// steigt mit jedem Abflug (kleiner Stoß)
    let launched: Int
    let style: MapStyle
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Durchmesser der Kugel
    static let size: CGFloat = 26
    /// Höhe des ganzen Elements (Kugel oben, Schrift darunter); die Mitte der Kugel liegt `orbOffset` über der Mitte
    static let height: CGFloat = 50
    static let orbOffset: CGFloat = height / 2 - 4 - size / 2

    private var active: Bool { status == .ordering }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                orb
                caption
            }
            .padding(.top, 4)
            .padding(.horizontal, 12)
            .frame(height: Self.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .accessibilityLabel(spoken)
        .accessibilityHint("Zeigt die Gedanken, die Paply noch ordnet.")
    }

    // MARK: Kugel

    private var orb: some View {
        let size = Self.size
        let still = reduce
        let lively = active && !still
        return ZStack {
            // Schein: atmet, solange geordnet wird (eigener Zweig – beginnt bei jedem Wechsel neu)
            ZStack {
                if lively {
                    glow
                        .phaseAnimator([false, true]) { view, inhale in
                            view
                                .opacity(inhale ? 0.75 : 0.42)
                                .scaleEffect(inhale ? 1.32 : 1.02)
                        } animation: { _ in
                            .easeInOut(duration: 1.5)
                        }
                        .transition(.opacity)
                } else {
                    glow
                        .opacity(active ? 0.42 : 0.18)
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: lively)
            .animation(.smooth, value: active)
            Circle()
                .fill(RadialGradient(colors: active ? [Color(uiColor: UIColor(hex: 0x9AF5BC)), .paplyGreenBright, .paplyGreenDeep]
                                                    : [Color.paplyGreen.opacity(0.75), Color.paplyGreenDeep.opacity(0.85), Color.paplyForest],
                                     center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.82))
                .frame(width: size, height: size)
            // Lichtschimmer, der über den Rand läuft – nur, solange geordnet wird
            ZStack {
                if lively {
                    shimmer
                        .keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                            view.rotationEffect(.degrees(angle))
                        } keyframes: { _ in
                            LinearKeyframe(360.0, duration: 2.2)
                        }
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: lively)
            Circle()
                .strokeBorder(Color.white.opacity(active ? 0.22 : 0.12), lineWidth: 0.6)
                .frame(width: size, height: size)
            Text("\(count)")
                .font(.system(size: count > 99 ? 9.5 : 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(active ? Color.paplyRecordInk : Color.paplyText)
                .contentTransition(.numericText(countsDown: true))
                .animation(reduce ? nil : .snappy(duration: 0.3), value: count)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size - 4)
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: 1.0, trigger: launched) { view, scale in
            view.scaleEffect(still ? 1 : scale)
        } keyframes: { _ in
            // ein Punkt hebt ab: kurz zusammenziehen, weich zurück
            CubicKeyframe(0.84, duration: 0.09)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
    }

    private var glow: some View {
        Circle()
            .fill(style.inbox)
            .frame(width: Self.size, height: Self.size)
            .blur(radius: 7)
    }

    private var shimmer: some View {
        Circle()
            .strokeBorder(AngularGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.85), location: 0.12),
                .init(color: .white.opacity(0), location: 0.3),
                .init(color: .white.opacity(0), location: 1),
            ], center: .center), lineWidth: 1.3)
            .frame(width: Self.size, height: Self.size)
    }

    private var caption: some View {
        HStack(spacing: 4) {
            if let icon {
                LucideImage(icon, size: 11, stroke: 2.2, relativeTo: .caption2)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, 4)
        .shadow(color: style.ground, radius: 2)
        .shadow(color: style.ground.opacity(0.8), radius: 4)
    }

    // MARK: Texte

    private var text: String {
        switch status {
        case .ordering: "Wird geordnet …"
        case .network: "Wartet auf Netz"
        case .key: "Schlüssel fehlt"
        case .limit: "Groq-Limit, später"
        case .budget: "Kontingent erreicht"
        case .attention: "Nicht verschriftlicht"
        }
    }

    private var icon: Lucide? {
        switch status {
        case .ordering: nil
        case .network: .wifiOff
        case .key: .keyRound
        case .limit, .budget: .hourglass
        case .attention: .triangleAlert
        }
    }

    private var tint: Color {
        switch status {
        case .key, .attention: style.dark ? Color.paplyBeak : Color(uiColor: UIColor(hex: 0xA86A00))
        default: style.secondary
        }
    }

    private var spoken: String {
        let things = count == 1 ? "1 Gedanke" : "\(count) Gedanken"
        switch status {
        case .ordering: return count == 1 ? "1 Gedanke wird geordnet" : "\(count) Gedanken werden geordnet"
        case .network: return "\(things), wartet auf Netz"
        case .key: return "\(things), Groq-Schlüssel fehlt"
        case .limit: return "\(things), Groq-Limit erreicht, später"
        case .budget: return "\(things), Kontingent für heute erreicht"
        case .attention: return "\(things), nicht verschriftlicht"
        }
    }
}

// MARK: - Knopf „Übersicht“

/// Erscheint, wenn die Karte verschoben oder gezoomt ist, und federt zurück auf „alles sichtbar“.
struct MapOverviewButton: View {
    let style: MapStyle
    /// im Fokus: zurück zum ganzen Thema
    let focused: Bool
    let action: () -> Void

    static let size: CGFloat = 38

    var body: some View {
        Button(action: action) {
            MapScanGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.9 * 17 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
                .foregroundStyle(PaplyStyle.usesGlass ? style.ink : Color.paplyText)
                .frame(width: Self.size, height: Self.size)
                .paplyGlass(.bar, interactive: true, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(focused ? "Thema ganz zeigen" : "Ganze Karte zeigen")
    }
}

/// Lucide „scan“ (v0.561): vier abgerundete Ecken, 24er-Raster
struct MapScanGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 12) * s, y: rect.midY + (y - 12) * s) }
        var path = Path()
        // M3 7V5a2 2 0 0 1 2-2h2
        path.move(to: p(3, 7))
        path.addArc(tangent1End: p(3, 3), tangent2End: p(5, 3), radius: 2 * s)
        path.addLine(to: p(7, 3))
        // M17 3h2a2 2 0 0 1 2 2v2
        path.move(to: p(17, 3))
        path.addArc(tangent1End: p(21, 3), tangent2End: p(21, 5), radius: 2 * s)
        path.addLine(to: p(21, 7))
        // M21 17v2a2 2 0 0 1-2 2h-2
        path.move(to: p(21, 17))
        path.addArc(tangent1End: p(21, 21), tangent2End: p(19, 21), radius: 2 * s)
        path.addLine(to: p(17, 21))
        // M7 21H5a2 2 0 0 1-2-2v-2
        path.move(to: p(7, 21))
        path.addArc(tangent1End: p(3, 21), tangent2End: p(3, 19), radius: 2 * s)
        path.addLine(to: p(3, 17))
        return path
    }
}
