import PaplyKit
import SwiftUI

/// „Landkarte“ der Gedanken (Entwurf docs/prototypes/paply-ios/gedanken-richtungen.html, Richtung 2).
///
/// Themen sind leuchtende Kreise (Größe = Anzahl, auf Wunsch mit Bild), Gedanken kleine Punkte auf einem Bogen
/// darüber, feine Linien zeigen Verknüpfungen. Die Anordnung kommt aus `MapLayout` (PaplyKit, im Hintergrund
/// gerechnet) und bleibt über gemerkte Anker (`MapAnchors`) an ihrem Platz – ein Kreis liegt jedes Mal genau dort.
///
/// Eingang: Gedanken, die gerade geordnet werden oder warten, stehen auf keinem Kreis (auch nicht unter „Ohne
/// Thema“). Sie zählen an einer kleinen Kugel unten mittig (`MapInboxOrb`, ohne Anker); ein Tipp darauf setzt
/// `focusedTopic = ThoughtsHome.pendingID`. Ist ein Gedanke fertig, fliegt ein Punkt mit weicher Feder von der Kugel
/// zu seinem Kreis und leuchtet dort auf; ein neues Thema wächst dabei an seinem Anker aus dem Nichts. Bei reduzierter
/// Bewegung und im Fokus erscheint er einfach.
///
/// Bedienung (`MapStageView`): Tipp auf einen Kreis (oder seinen Namen) setzt `focusedTopic`, die Kamera fährt mit
/// weicher Feder hinein; Tipp auf einen Punkt öffnet den Gedanken (`onOpenThought`); Tipp auf freie Fläche setzt
/// `focusedTopic = nil`. Mit einem Finger verschieben, mit zweien zoomen, Doppeltipp zoomt an der Stelle hinein bzw.
/// bei starkem Zoom zurück. Ist die Karte verschoben, erscheint der Knopf „Übersicht“. Die Ansicht ist nur Ansicht:
/// Anker ändern sich nie, nichts wird gespeichert.
///
/// Kennungen für `focusedTopic`: Themen-ID, `noTopicID` („Ohne Thema“), `moreID` (Sammelkreis „Weitere
/// Themen“ – Gedanken dazu liefert `ThoughtsModel.mapCollectedThoughts()`) oder `ThoughtsHome.pendingID` (Panel
/// „Noch nicht geordnet“: Karte bleibt in der Übersicht, die Kugel tritt zurück).
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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var engine = MapEngine()
    @State private var motion = MapMotion()
    @State private var hitBox = MapHitBox()
    @State private var images = MapImageCache()
    @State private var stageMemory = MapStageMemory()
    @State private var lastFocus: String?
    /// weckt die Karte zu geplanten Zeitpunkten (Abflug, Landung, Ende eines Übergangs)
    @State private var clock = 0
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
        let inbox = MapInbox(model: model)
        let focus = Self.validFocus(focusedTopic, scene)
        // Flüge nur, wenn die Kugel zu sehen ist: Übersicht, Panel „Noch nicht geordnet“ zu, Bewegung an
        let flights = !reduceMotion && focus == nil && focusedTopic != ThoughtsHome.pendingID
        let _ = motion.update(scene, inbox: inbox, flights: flights, bubbleOf: { engine.bubble(ofThought: $0) }, now: now)
        let _ = clock // geweckt: neu zeichnen (Zahl der Kugel, Zeitleiste anhalten)
        // nächste Frist (Abflug, Landung, Ende eines Übergangs, Ende des Wartens): Jede neue plant den Wecker neu
        let wakeAt = motion.nextWake(after: now)
        let style = MapStyle(scheme)
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let size = CGSize(width: outer.size.width + insets.leading + insets.trailing,
                              height: outer.size.height + insets.top + insets.bottom)
            let stage = MapStage(size: size, top: insets.top, bottom: max(bottomInset, insets.bottom))
            MapStageView(
                scene: scene, motion: motion,
                inbox: MapStageView.Inbox(count: motion.inboxCount(at: now), launched: motion.launched(at: now),
                                          status: inbox.status ?? .ordering),
                focusedTopic: $focusedTopic, focusID: focus ?? lastFocus, proposed: stage, style: style,
                ready: request != nil && engine.layout != nil, legend: showsLegend(scene),
                loaded: model.isLoaded, hasThoughts: !model.thoughts.isEmpty,
                hitBox: hitBox, images: images, stageMemory: stageMemory, reduceMotion: reduceMotion, voiceOver: voiceOver,
                onOpenThought: onOpenThought)
                .frame(width: size.width, height: size.height)
                .offset(x: -insets.leading, y: -insets.top)
        }
        .background { style.background }
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
        .task(id: wakeAt) { await wake(at: wakeAt) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Karte der Gedanken")
        .accessibilityAction(.escape) {
            if focusedTopic != nil { focusedTopic = nil }
        }
    }

    /// Zur nächsten Frist neu zeichnen (Abflug: Zahl sinkt; Ende: die Zeitleiste hält an). Das Neuzeichnen
    /// liefert die nächste Frist und damit einen neuen Wecker – bis alles Geplante vorbei ist. Nichts läuft dauerhaft.
    private func wake(at date: Date?) async {
        guard let date else { return }
        try? await Task.sleep(for: .seconds(max(0.01, date.timeIntervalSinceNow + 0.02)))
        guard !Task.isCancelled else { return }
        clock &+= 1
    }

    static func validFocus(_ focusedTopic: String?, _ scene: MapScene) -> String? {
        guard let focusedTopic, scene.layout.bubble(focusedTopic) != nil else { return nil }
        return focusedTopic
    }

    private func showsLegend(_ scene: MapScene) -> Bool {
        scene.total > 0 && (scene.total <= 12 || !legendSeen)
    }

    // MARK: Bühne und Kamera

    /// Unten frei gehaltenes Band in der Übersicht (Kugel des Eingangs bzw. Legende) – immer gleich, damit die Karte
    /// nicht springt, wenn die Kugel kommt oder geht
    static let band: CGFloat = 52

    /// Mitte der Kugel (und Start der Flüge): unten mittig über dem unteren Rand der Bühne
    static func orbCenter(_ stage: MapStage) -> CGPoint {
        CGPoint(x: stage.size.width / 2, y: stage.size.height - stage.bottom - band / 2 - MapInboxOrb.orbOffset)
    }

    /// Unter Kopf und Statusleiste blendet die Karte weich aus (gedimmte Nachbarn im Fokus ragen sonst hinein)
    static func topFade(_ stage: MapStage) -> some View {
        let h = max(stage.size.height, 1)
        let start = max(0, stage.top - 6) / h, end = min(1, (stage.top + 22) / h)
        return LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: start),
                                      .init(color: .black, location: end), .init(color: .black, location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

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
    static func camera(scene: MapScene, focus: String?, stage: MapStage) -> MapCamera {
        let visible = stage.visible
        let overview = overviewCamera(scene: scene, stage: stage)
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

    /// Ganze Karte im sichtbaren Bereich über dem Band unten
    static func overviewCamera(scene: MapScene, stage: MapStage) -> MapCamera {
        let bounds = scene.layout.bounds
        guard bounds.width > 0, bounds.height > 0 else { return .identity }
        var area = stage.visible.insetBy(dx: 18, dy: 12)
        area.size.height = max(40, area.height - (band - 12))
        let zoom = max(0.05, min(1.8, area.width / bounds.width, area.height / bounds.height))
        let anchor = stage.anchor
        return MapCamera(zoom: zoom, center: CGPoint(x: bounds.midX - (area.midX - anchor.x) / zoom,
                                                     y: bounds.midY - (area.midY - anchor.y) / zoom))
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
struct CameraMotion: ViewModifier {
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
