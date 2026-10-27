import PaplyKit
import SwiftUI

/// „Landkarte“ der Gedanken (Entwurf docs/prototypes/paply-ios/gedanken-richtungen.html, Richtung 2).
///
/// Themen sind leuchtende Kreise (Größe = Anzahl), Gedanken kleine Punkte auf einem Bogen darüber, feine
/// Linien zeigen Verknüpfungen. Die Anordnung kommt aus `MapLayout` (PaplyKit, im Hintergrund gerechnet) und
/// bleibt über gemerkte Anker (`MapAnchors`) an ihrem Platz – ein Kreis liegt jedes Mal genau dort.
///
/// Bedienung: Tipp auf einen Kreis (oder seinen Namen) setzt `focusedTopic`, die Kamera fährt mit weicher
/// Feder hinein; Tipp auf einen Punkt öffnet den Gedanken (`onOpenThought`); Tipp auf freie Fläche setzt
/// `focusedTopic = nil`. Ohne Fokus passt die Karte immer ganz auf den Bildschirm – kein Ziehen, kein Zoomen.
///
/// Kennungen für `focusedTopic`: Themen-ID, `noTopicID` („Ohne Thema“) oder `moreID` (Sammelkreis „Weitere
/// Themen“ – Gedanken dazu liefert `ThoughtsModel.mapCollectedThoughts()`).
///
/// Platz: Oben gilt der sichere Bereich der Ansicht (Kopfzeilen per `.safeAreaPadding(.top, …)` o. ä.),
/// unten `bottomInset` (vom Panel verdeckte Höhe) bzw. der sichere Bereich, je nachdem was größer ist. Bleibt
/// darüber zu wenig Platz (Panel ganz oben), behält die Kamera ihre letzte Einstellung. Die Ansicht zeichnet
/// ihren Hintergrund selbst randlos.
struct ThoughtMapView: View {
    /// Pseudo-Thema „Ohne Thema“ (`focusedTopic` == noTopicID → Gedanken ohne Thema)
    static let noTopicID = "_none"
    /// Sammelkreis „Weitere Themen“ (`focusedTopic` == moreID → `ThoughtsModel.mapCollectedThoughts()`)
    static let moreID = MapLayout.moreID

    /// nil = Übersicht; sonst hineingezoomt (animiert)
    @Binding var focusedTopic: String?
    /// vom Panel verdeckte Höhe: Die Kamera rückt das Thema in den sichtbaren Teil darüber
    var bottomInset: CGFloat
    var onOpenThought: (String) -> Void

    @Environment(ThoughtsModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = MapEngine()
    @State private var motion = MapMotion()
    @State private var hitBox = MapHitBox()
    @State private var stageMemory = MapStageMemory()
    @State private var lastFocus: String?
    @State private var taps = 0
    @State private var settled = 0
    /// Legende nur beim ersten Mal (bis ein Thema geöffnet wurde) bzw. bei wenigen Gedanken
    @AppStorage("paply.map.legendSeen") private var legendSeen = false

    init(focusedTopic: Binding<String?>, bottomInset: CGFloat = 0, onOpenThought: @escaping (String) -> Void) {
        _focusedTopic = focusedTopic
        self.bottomInset = bottomInset
        self.onOpenThought = onOpenThought
    }

    /// Feder der Kamera (wie die „Zoom“-Feder des Entwurfs: k 110, c 20,5 – ruhig, ohne Nachwippen)
    static let cameraSpring = Animation.interpolatingSpring(mass: 1, stiffness: 110, damping: 21)

    var body: some View {
        let anchors = MapAnchors.shared
        let now = Date()
        // Vor dem ersten Entsperren sind die gemerkten Plätze nicht lesbar: dann nichts anlegen und nichts zeichnen.
        // `revision` ist beobachtet: Nachgeladene Plätze lösen eine neue Anfrage aus.
        let request = anchors.isReady
            ? MapEngine.makeRequest(model: model, anchors: anchors.anchors, anchorRevision: anchors.revision) : nil
        let scene = engine.scene(model: model, total: request?.total ?? 0, now: now) ?? .empty
        let _ = motion.update(scene, now: now)
        let _ = settled // nach Übergängen neu zeichnen, damit die Zeitleiste anhält
        let style = MapStyle(scheme)
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let size = CGSize(width: outer.size.width + insets.leading + insets.trailing,
                              height: outer.size.height + insets.top + insets.bottom)
            let stage = MapStage(size: size, top: insets.top, bottom: max(bottomInset, insets.bottom))
            stageView(scene: scene, stage: stage, style: style, now: now, ready: request != nil && engine.layout != nil)
                .frame(width: size.width, height: size.height)
                .offset(x: -insets.leading, y: -insets.top)
        }
        .background { style.background }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.75), trigger: taps)
        .onAppear { anchors.prepare() }
        .onChange(of: request, initial: true) { _, request in
            guard let request else { return }
            engine.request(request, persist: model.isLoaded)
        }
        .onChange(of: focusedTopic, initial: true) { _, id in
            guard let id else { return }
            lastFocus = id
            if !legendSeen { legendSeen = true }
        }
        .task(id: scene.version) {
            let rest = motion.remaining(at: Date())
            guard rest > 0 else { return }
            try? await Task.sleep(for: .seconds(rest + 0.05))
            settled &+= 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Karte der Gedanken")
        .accessibilityAction(.escape) {
            if focusedTopic != nil { focusedTopic = nil }
        }
    }

    // MARK: Bühne

    private func validFocus(_ scene: MapScene) -> String? {
        guard let focusedTopic, scene.layout.bubble(focusedTopic) != nil else { return nil }
        return focusedTopic
    }

    private func showsLegend(_ scene: MapScene) -> Bool {
        scene.total > 0 && (scene.total <= 12 || !legendSeen)
    }

    @ViewBuilder
    private func stageView(scene: MapScene, stage proposed: MapStage, style: MapStyle, now: Date, ready: Bool) -> some View {
        let focus = validFocus(scene)
        let legend = showsLegend(scene)
        let stage = stageMemory.usable(proposed, needs: Self.neededHeight(scene: scene, focus: focus))
        let target = Self.camera(scene: scene, focus: focus, stage: stage, legend: legend)
        let running = motion.isRunning(at: now)
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: !running)) { timeline in
                let date = running ? timeline.date : Date()
                MapCanvas(scene: scene, previous: motion.previous, progress: motion.progress(at: date),
                          appear: appearance(scene, at: date), camera: target, stage: stage,
                          focusLevel: focus == nil ? 0 : 1, focusID: focus ?? lastFocus, style: style,
                          reduceMotion: reduceMotion, hitBox: hitBox,
                          onTopic: { select($0) }, onThought: onOpenThought)
            }
            .modifier(CameraMotion(focus: focus, version: scene.version, reduceMotion: reduceMotion))
            .mask(Self.topFade(proposed))

            if legend {
                Text(scene.total <= 2 ? "Mit jedem Gedanken wächst deine Karte."
                     : scene.layout.topicLines.isEmpty ? "Größer = mehr Gedanken" : "Größer = mehr Gedanken · Linien = gehört zusammen")
                    .font(.caption)
                    .foregroundStyle(style.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .position(x: stage.size.width / 2, y: stage.size.height - stage.bottom - 20)
                    .opacity(focus == nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: focus)
                    .allowsHitTesting(false)
            }
            if ready, scene.layout.bubbles.isEmpty, model.isLoaded {
                // noch nichts auf der Karte: leer – oder der erste Gedanke wird gerade geordnet
                let ordering = !model.thoughts.isEmpty
                VStack(spacing: 6) {
                    Text(ordering ? "Dein Gedanke wird geordnet …" : "Noch keine Gedanken")
                        .font(.headline)
                        .foregroundStyle(style.ink)
                    Text(ordering ? "Gleich bekommt er seinen Platz auf der Karte." : "Mit jedem Gedanken wächst deine Karte.")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .position(stage.anchor)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in handleTap(location, scene: scene) }
    }

    /// Unter Kopf und Statusleiste blendet die Karte weich aus (gedimmte Nachbarn im Fokus ragen sonst hinein)
    private static func topFade(_ stage: MapStage) -> some View {
        let h = max(stage.size.height, 1)
        let start = max(0, stage.top - 6) / h, end = min(1, (stage.top + 22) / h)
        return LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: start),
                                      .init(color: .black, location: end), .init(color: .black, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

    private func appearance(_ scene: MapScene, at date: Date) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for dot in scene.layout.dots {
            if let a = motion.appearance(dot.id, at: date) { result[dot.id] = a }
        }
        for bubble in scene.layout.bubbles {
            let key = "topic:" + bubble.id
            if let a = motion.appearance(key, at: date) { result[key] = a }
        }
        return result
    }

    // MARK: Kamera

    /// So hoch muss der sichtbare Teil mindestens sein, damit die Kamera neu rechnet: im Fokus der ganze Kreis
    /// samt Bogen (2 × Außenradius), in der Übersicht ein brauchbarer Streifen.
    static func neededHeight(scene: MapScene, focus: String?) -> CGFloat {
        guard let focus, let bubble = scene.layout.bubble(focus) else { return 120 }
        return max(120, 2 * bubble.outerRadius)
    }

    /// Übersicht: ganze Karte im sichtbaren Bereich (bei wenigen Themen bis 1,8-fach).
    /// Fokus: nur so nah, dass die Punkte gut zu treffen sind (≈ 26 pt Abstand, 1,35- bis 2,2-fach) – die
    /// Nachbarn bleiben am Rand gedimmt sichtbar, man behält die Orientierung. Bogen und Kreis passen immer
    /// in den sichtbaren Teil über dem Panel.
    static func camera(scene: MapScene, focus: String?, stage: MapStage, legend: Bool) -> MapCamera {
        let visible = stage.visible
        let overview = overviewCamera(scene: scene, stage: stage, legend: legend)
        if let focus, let bubble = scene.layout.bubble(focus) {
            let area = visible.insetBy(dx: 22, dy: 18)
            let width = 2 * bubble.outerRadius
            let height = bubble.outerRadius + bubble.radius // Bogen oben bis Unterkante des Kreises
            let fit = min(area.width / width, area.height / height)
            let own = scene.layout.dots.filter { $0.topicID == focus }.sorted { $0.rank < $1.rank }
            let spacing = own.count >= 2 ? hypot(own[0].position.x - own[1].position.x, own[0].position.y - own[1].position.y)
                : MapLayoutConfig().maxDotSpacing
            let wanted = min(2.2, max(1.35, 26 / max(spacing, 1), overview.zoom * 1.25))
            let zoom = max(0.5, min(fit, wanted))
            return MapCamera(zoom: zoom, center: CGPoint(x: bubble.center.x, y: bubble.center.y - (bubble.outerRadius - bubble.radius) / 2))
        }
        return overview
    }

    private static func overviewCamera(scene: MapScene, stage: MapStage, legend: Bool) -> MapCamera {
        let bounds = scene.layout.bounds
        guard bounds.width > 0, bounds.height > 0 else { return .identity }
        var area = stage.visible.insetBy(dx: 18, dy: 12)
        if legend { area.size.height -= 28 }
        area.size.height = max(40, area.height)
        let zoom = max(0.05, min(1.8, area.width / bounds.width, area.height / bounds.height))
        let anchor = stage.anchor
        return MapCamera(zoom: zoom, center: CGPoint(x: bounds.midX - (area.midX - anchor.x) / zoom,
                                                     y: bounds.midY - (area.midY - anchor.y) / zoom))
    }

    // MARK: Tippen

    private func select(_ id: String) {
        taps &+= 1
        if focusedTopic != id { focusedTopic = id }
    }

    /// Reihenfolge: Titel → Punkte des Themas im Fokus → Kreise → Namen → andere Punkte → freie Fläche.
    /// Treffbereiche ≥ 44 pt; bei dicht liegenden Punkten gewinnt der nächste.
    private func handleTap(_ location: CGPoint, scene: MapScene) {
        let hits = hitBox.snapshot
        let focus = validFocus(scene)
        func distance(_ p: CGPoint) -> CGFloat { hypot(p.x - location.x, p.y - location.y) }

        let titles = hits.titles.filter { $0.rect.insetBy(dx: -6, dy: -4).contains(location) }
        if let title = titles.min(by: { distance(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) < distance(CGPoint(x: $1.rect.midX, y: $1.rect.midY)) }) {
            onOpenThought(title.id)
            return
        }
        if let focus, let dot = hits.dots.filter({ $0.topicID == focus && distance($0.center) <= 26 }).min(by: { distance($0.center) < distance($1.center) }) {
            onOpenThought(dot.id)
            return
        }
        let circles = hits.topics.filter { distance($0.center) <= max($0.radius + 8, 24) }
        if let topic = circles.min(by: { distance($0.center) - $0.radius < distance($1.center) - $1.radius }) {
            select(topic.id)
            return
        }
        if let topic = hits.topics.first(where: { $0.label?.insetBy(dx: -8, dy: -8).contains(location) == true }) {
            select(topic.id)
            return
        }
        if let dot = hits.dots.filter({ distance($0.center) <= 22 }).min(by: { distance($0.center) < distance($1.center) }) {
            // eindeutig (Punkte weit genug auseinander) → öffnen, sonst erst das Thema zeigen
            if focus == nil, dot.spacing >= 28 { onOpenThought(dot.id) } else { select(dot.topicID) }
            return
        }
        if focusedTopic != nil { focusedTopic = nil }
    }
}

/// Letzte brauchbare Bühne: Verdeckt das Panel fast alles (Raststufe „groß“), rechnet die Kamera nicht mit
/// einem winzigen Streifen (das ergäbe einen Maßstab nahe 0), sondern bleibt, wo sie war. Reine Buchführung
/// im `body`, löst nichts aus.
@MainActor
final class MapStageMemory {
    private var last: MapStage?

    func usable(_ stage: MapStage, needs height: CGFloat) -> MapStage {
        let free = stage.size.height - stage.top - stage.bottom
        if free >= height {
            last = stage
            return stage
        }
        if var kept = last, kept.size == stage.size, kept.top == stage.top {
            kept.bottom = min(kept.bottom, max(0, stage.size.height - stage.top - height))
            return kept
        }
        // noch nichts gemerkt (oder Größe geändert): unten nur so weit verdecken, dass es reicht
        var fallback = stage
        fallback.bottom = max(0, stage.size.height - stage.top - height)
        return fallback
    }
}

/// Kamera und Fokus: weiche Feder; bei reduzierter Bewegung ohne Flug, nur Überblenden.
private struct CameraMotion: ViewModifier {
    let focus: String?
    let version: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            ZStack {
                content
                    .id(focus ?? "_overview")
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.22), value: focus)
        } else {
            content
                .animation(ThoughtMapView.cameraSpring, value: focus)
                .animation(.smooth(duration: 0.55), value: version)
        }
    }
}
