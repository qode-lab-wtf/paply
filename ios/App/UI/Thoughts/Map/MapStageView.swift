import PaplyKit
import SwiftUI

// Bühne der Karte: Zeichenfläche mit Gesten, Kugel des Eingangs, Knopf „Übersicht“, Legende.
//
// Gesten (die Karte darüber rechnet dabei nichts neu – nur diese Ansicht zeichnet):
// - Tipp: sofort. Kreis oder Name → Fokus, Punkt → Gedanke öffnen, freie Fläche → Fokus lösen (wartet kurz, ob ein
//   zweiter Tipp folgt). Zwei Tipps kurz hintereinander auf freier Fläche = Doppeltipp.
// - Ein Finger verschiebt, zwei zoomen um ihre Mitte (`MapViewport`: Grenzen mit Gummiband, beim Loslassen weich
//   zurück, Schwung nach dem Wischen). Beides geht auch im Fokus.
// - Doppeltipp zoomt an der Stelle zweifach hinein, bei starkem Zoom zurück zur Übersicht.
//
// Freie Ansicht: Die Übersicht und jedes Thema im Fokus haben eine eigene. Schließt das Panel, geht es zurück zur
// letzten freien Ansicht der Übersicht – dort war man, das ist das Ruhigste. Die Kamera wird nie gespeichert und
// ändert keinen Anker. Mit VoiceOver gilt immer die Übersicht (alle Elemente im Bild).

struct MapStageView: View {
    struct Inbox: Equatable {
        var count: Int
        var launched: Int
        var status: MapInboxStatus
    }

    let scene: MapScene
    let motion: MapMotion
    let inbox: Inbox
    @Binding var focusedTopic: String?
    /// zuletzt fokussiertes Thema (bleibt beim Herauszoomen gesetzt, damit es weich zurücktritt)
    let focusID: String?
    let proposed: MapStage
    let style: MapStyle
    let ready: Bool
    let legend: Bool
    let loaded: Bool
    let hasThoughts: Bool
    let hitBox: MapHitBox
    let images: MapImageCache
    let stageMemory: MapStageMemory
    let reduceMotion: Bool
    let voiceOver: Bool
    let onOpenThought: (String) -> Void

    /// verschobene bzw. gezoomte Übersicht (nil = alles sichtbar)
    @State private var free: MapCamera?
    /// verschobene Ansicht im Fokus – gilt nur für dieses Thema
    @State private var focusFree: FocusCamera?
    @State private var drag = MapDrag()
    @GestureState private var panning = false
    @GestureState private var pinching = false
    @State private var lastGestureEnd = Date.distantPast
    @State private var lastTap: (date: Date, location: CGPoint)?
    @State private var deselect: Task<Void, Never>?
    @State private var taps = 0
    #if DEBUG
    @State private var debugCameraApplied = false
    #endif

    private struct FocusCamera {
        var id: String
        var camera: MapCamera
    }

    /// Laufende Geste
    private struct MapDrag {
        /// Ansicht unter den Fingern (ohne Gummiband); nil = keine Geste
        var raw: MapCamera?
        /// gezeigte Ansicht (mit Gummiband)
        var shown: MapCamera?
        /// Ansicht und Fingerstand zu Beginn des aktuellen Abschnitts (Wechsel Ziehen ↔ Zoomen)
        var base = MapCamera.identity
        var origin: CGSize = .zero
        var translation: CGSize = .zero
        /// Mitte des Zooms
        var anchor: CGPoint = .zero
        var location: CGPoint?
        var velocity: CGSize = .zero
        var panning = false
        var pinching = false
        var pinched = false
        /// Fokus zu Beginn: Die Ansicht gehört zu ihm
        var focus: String?
    }

    // MARK: Geometrie

    private struct Geometry {
        var focus: String?
        var stage: MapStage
        var home: MapCamera
        var viewport: MapViewport
    }

    private func geometry() -> Geometry {
        let focus = ThoughtMapView.validFocus(focusedTopic, scene)
        let stage = stageMemory.usable(proposed, needs: ThoughtMapView.neededHeight(scene: scene, focus: focus))
        let home = ThoughtMapView.camera(scene: scene, focus: focus, stage: stage)
        let overview = ThoughtMapView.overviewCamera(scene: scene, stage: stage)
        return Geometry(focus: focus, stage: stage, home: home,
                        viewport: MapViewport(visible: stage.visible, bounds: scene.layout.bounds, overviewZoom: overview.zoom))
    }

    /// Freie Ansicht, die gerade gilt (nil = Übersicht bzw. Thema ganz)
    private func resting(_ focus: String?) -> MapCamera? {
        guard !voiceOver else { return nil }
        if let focus { return focusFree?.id == focus ? focusFree?.camera : nil }
        return free
    }

    // MARK: Ansicht

    var body: some View {
        let g = geometry()
        let resting = resting(g.focus)
        let camera = drag.shown ?? resting ?? g.home
        let moved = !voiceOver && g.viewport.differs(camera, from: g.home)
        let running = motion.isRunning(at: Date())
        let pendingOpen = focusedTopic == ThoughtsHome.pendingID
        let orbShown = ready && inbox.count > 0 && g.focus == nil && !pendingOpen
        let orb = ThoughtMapView.orbCenter(g.stage)
        let interactive = ready && !scene.layout.bubbles.isEmpty
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: !running)) { timeline in
                let date = running ? timeline.date : Date()
                MapCanvas(scene: scene, previous: motion.previous, progress: motion.progress(at: date),
                          appear: appearance(at: date), camera: camera, stage: g.stage,
                          focusLevel: g.focus == nil ? 0 : 1, focusID: focusID, style: style,
                          reduceMotion: reduceMotion, hitBox: hitBox, images: images,
                          flights: motion.flights(at: date), unlanded: motion.unlanded(at: date), glows: motion.glows(at: date),
                          orb: orb, onTopic: { select($0) }, onThought: onOpenThought)
            }
            .modifier(CameraMotion(focus: g.focus, version: scene.version, reduceMotion: reduceMotion))
            .mask(ThoughtMapView.topFade(proposed))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap($0.location) }, including: interactive ? .all : .subviews)
            .simultaneousGesture(pan, including: interactive ? .all : .subviews)
            .simultaneousGesture(pinch, including: interactive ? .all : .subviews)

            if legend {
                Text(scene.total <= 2 ? "Mit jedem Gedanken wächst deine Karte."
                     : scene.layout.topicLines.isEmpty ? "Größer = mehr Gedanken" : "Größer = mehr Gedanken · Linien = gehört zusammen")
                    .font(.caption)
                    .foregroundStyle(style.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .position(x: g.stage.size.width / 2, y: g.stage.size.height - g.stage.bottom - 18)
                    .opacity(g.focus == nil && !orbShown && !moved ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: g.focus == nil && !orbShown && !moved)
                    .allowsHitTesting(false)
            }
            if ready, scene.layout.bubbles.isEmpty, loaded {
                // noch nichts auf der Karte: leer – oder der erste Gedanke wird gerade geordnet
                VStack(spacing: 6) {
                    Text(hasThoughts ? "Dein Gedanke wird geordnet …" : "Noch keine Gedanken")
                        .font(.headline)
                        .foregroundStyle(style.ink)
                    Text(hasThoughts ? "Gleich bekommt er seinen Platz auf der Karte." : "Mit jedem Gedanken wächst deine Karte.")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .position(g.stage.anchor)
                .allowsHitTesting(false)
            }

            ZStack {
                if orbShown {
                    MapInboxOrb(count: inbox.count, status: inbox.status, launched: inbox.launched, style: style) {
                        cancelDeselect()
                        focusedTopic = ThoughtsHome.pendingID
                    }
                    .position(x: orb.x, y: orb.y + MapInboxOrb.orbOffset)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
                if moved, !voiceOver {
                    MapOverviewButton(style: style, focused: g.focus != nil) { returnHome(g.focus) }
                        .position(x: g.stage.size.width - 16 - MapOverviewButton.size / 2, y: orb.y)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(PaplyMotion.bouncy(reduceMotion), value: orbShown)
            .animation(PaplyMotion.smooth(reduceMotion), value: moved)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.75), trigger: taps)
        .onChange(of: pinching) { _, active in if !active { pinchStopped() } }
        .onChange(of: panning) { _, active in if !active { panStopped() } }
        .onChange(of: g.focus) { _, focus in
            // neues Thema im Fokus: seine Ansicht beginnt ganz
            if focusFree != nil, focusFree?.id != focus { focusFree = nil }
        }
        #if DEBUG
        .onChange(of: scene.version, initial: true) { _, _ in applyDebugCamera() }
        #endif
    }

    private func appearance(at date: Date) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for (key, _) in motion.appear {
            if let a = motion.appearance(key, at: date) { result[key] = a }
        }
        return result
    }

    // MARK: Verschieben und Zoomen

    private var pan: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($panning) { _, state, _ in state = true }
            .onChanged { value in panChanged(value) }
            .onEnded { value in
                drag.velocity = value.velocity
                drag.location = value.location
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($pinching) { _, state, _ in state = true }
            .onChanged { value in pinchChanged(value) }
    }

    /// Beginn einer Geste: von der Ansicht aus, die gerade zu sehen ist
    private func begin(_ d: inout MapDrag, _ g: Geometry) {
        guard d.raw == nil else { return }
        let start = resting(g.focus) ?? g.home
        d.raw = start
        d.shown = start
        d.base = start
        d.focus = g.focus
        cancelDeselect()
    }

    private func panChanged(_ value: DragGesture.Value) {
        let g = geometry()
        var d = drag
        begin(&d, g)
        if !d.panning {
            d.panning = true
            d.base = d.raw ?? g.home
            d.origin = value.translation
        }
        d.translation = value.translation
        d.location = value.location
        if !d.pinching, let _ = d.raw {
            let t = CGSize(width: value.translation.width - d.origin.width, height: value.translation.height - d.origin.height)
            let raw = g.viewport.panned(d.base, by: t)
            d.raw = raw
            d.shown = g.viewport.rubberBanded(raw, around: value.location)
        }
        drag = d
    }

    private func pinchChanged(_ value: MagnifyGesture.Value) {
        let g = geometry()
        var d = drag
        begin(&d, g)
        if !d.pinching {
            d.pinching = true
            d.pinched = true
            d.base = d.raw ?? g.home
            d.anchor = value.startLocation
        }
        let raw = g.viewport.zoomed(d.base, to: d.base.zoom * value.magnification, around: d.anchor)
        d.raw = raw
        d.shown = g.viewport.rubberBanded(raw, around: d.anchor)
        drag = d
    }

    private func pinchStopped() {
        guard drag.pinching else { return }
        drag.pinching = false
        if drag.panning {
            // ein Finger bleibt: von hier aus weiter verschieben
            drag.base = drag.raw ?? drag.base
            drag.origin = drag.translation
        } else {
            finish()
        }
    }

    private func panStopped() {
        guard drag.panning else { return }
        drag.panning = false
        if !drag.pinching { finish() }
    }

    /// Loslassen: zurück in die Grenzen (weich), nach einem Wisch mit Schwung. Liegt die Ansicht wieder auf der
    /// Übersicht, gilt sie als Übersicht (kein Knopf).
    private func finish() {
        let d = drag
        guard let raw = d.raw else {
            drag = MapDrag()
            return
        }
        let g = geometry()
        let viewport = g.viewport
        let point = d.pinched ? d.anchor : (d.location ?? viewport.anchor)
        var target = viewport.settled(raw, around: point)
        let overshoot = viewport.differs(raw, from: target)
        var animation = Animation.interpolatingSpring(mass: 1, stiffness: 170, damping: 26)
        let speed = hypot(d.velocity.width, d.velocity.height)
        if !overshoot, !d.pinched, speed > 220 {
            let flung = viewport.flung(target, velocity: d.velocity)
            let distance = hypot(flung.center.x - target.center.x, flung.center.y - target.center.y) * target.zoom
            if distance > 2 {
                target = flung
                // Schwung: startet mit der Geschwindigkeit des Fingers, kommt ohne Nachwippen zur Ruhe
                animation = .interpolatingSpring(mass: 1, stiffness: 60, damping: 15.5, initialVelocity: min(6, speed / distance))
            }
        }
        lastGestureEnd = Date()
        guard d.focus == g.focus else {
            // der Fokus hat während der Geste gewechselt: dessen Kamera gilt
            drag = MapDrag()
            return
        }
        let keep: MapCamera? = viewport.differs(target, from: g.home) ? target : nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : animation) {
            drag = MapDrag()
            store(keep, focus: g.focus)
        }
    }

    private func store(_ camera: MapCamera?, focus: String?) {
        if let focus {
            focusFree = camera.map { FocusCamera(id: focus, camera: $0) }
        } else {
            free = camera
        }
    }

    /// Knopf „Übersicht“: alles sichtbar (im Fokus: das ganze Thema)
    private func returnHome(_ focus: String?) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : ThoughtMapView.cameraSpring) {
            store(nil, focus: focus)
        }
    }

    /// Doppeltipp: zweifach hinein an der Stelle, bei starkem Zoom zurück
    private func zoom(at location: CGPoint) {
        let g = geometry()
        let current = resting(g.focus) ?? g.home
        let next = g.viewport.doubleTapped(current, at: location)
        let keep = next.flatMap { g.viewport.differs($0, from: g.home) ? $0 : nil }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : ThoughtMapView.cameraSpring) {
            store(keep, focus: g.focus)
        }
    }

    // MARK: Tippen

    private func select(_ id: String) {
        cancelDeselect()
        guard focusedTopic != id else { return }
        taps &+= 1
        focusedTopic = id
    }

    private func cancelDeselect() {
        deselect?.cancel()
        deselect = nil
    }

    /// Sofort: Kreis, Name, Punkt, Titel. Freie Fläche wartet kurz, ob ein zweiter Tipp folgt (Doppeltipp).
    private func tap(_ location: CGPoint) {
        // direkt nach einer Geste zählt kein Tipp
        guard drag.raw == nil, Date().timeIntervalSince(lastGestureEnd) > 0.15 else { return }
        let now = Date()
        if let last = lastTap, now.timeIntervalSince(last.date) < 0.32,
           hypot(location.x - last.location.x, location.y - last.location.y) < 44 {
            lastTap = nil
            cancelDeselect()
            zoom(at: location)
            return
        }
        if hit(location) {
            lastTap = nil
            return
        }
        lastTap = (now, location)
        guard focusedTopic != nil else { return }
        cancelDeselect()
        deselect = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            if focusedTopic != nil { focusedTopic = nil }
        }
    }

    /// Reihenfolge: Titel → Punkte des Themas im Fokus → Kreise → Namen → andere Punkte. Treffbereiche ≥ 44 pt; bei
    /// dicht liegenden Punkten gewinnt der nächste. false = freie Fläche.
    private func hit(_ location: CGPoint) -> Bool {
        let hits = hitBox.snapshot
        let focus = ThoughtMapView.validFocus(focusedTopic, scene)
        func distance(_ p: CGPoint) -> CGFloat { hypot(p.x - location.x, p.y - location.y) }

        let titles = hits.titles.filter { $0.rect.insetBy(dx: -6, dy: -4).contains(location) }
        if let title = titles.min(by: { distance(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) < distance(CGPoint(x: $1.rect.midX, y: $1.rect.midY)) }) {
            onOpenThought(title.id)
            return true
        }
        if let focus, let dot = hits.dots.filter({ $0.topicID == focus && distance($0.center) <= 26 }).min(by: { distance($0.center) < distance($1.center) }) {
            onOpenThought(dot.id)
            return true
        }
        let circles = hits.topics.filter { distance($0.center) <= max($0.radius + 8, 24) }
        if let topic = circles.min(by: { distance($0.center) - $0.radius < distance($1.center) - $1.radius }) {
            select(topic.id)
            return true
        }
        if let topic = hits.topics.first(where: { $0.label?.insetBy(dx: -8, dy: -8).contains(location) == true }) {
            select(topic.id)
            return true
        }
        if let dot = hits.dots.filter({ distance($0.center) <= 22 }).min(by: { distance($0.center) < distance($1.center) }) {
            // eindeutig (Punkte weit genug auseinander) → öffnen, sonst erst das Thema zeigen
            if focus == nil, dot.spacing >= 28 { onOpenThought(dot.id) } else { select(dot.topicID) }
            return true
        }
        return false
    }

    // MARK: Debug

    #if DEBUG
    /// `-PaplyMapCamera <Zoom>,<dx>,<dy>`: Übersicht verschoben/gezoomt starten (Zoom als Vielfaches der Übersicht,
    /// Versatz in Kartenpunkten) – für Bildschirmfotos
    private func applyDebugCamera() {
        guard !debugCameraApplied, ready, !scene.layout.bubbles.isEmpty else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-PaplyMapCamera"), i + 1 < args.count else { return }
        let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return }
        debugCameraApplied = true
        let g = geometry()
        let home = g.home
        let camera = MapCamera(zoom: home.zoom * CGFloat(parts[0]),
                               center: CGPoint(x: home.center.x + CGFloat(parts[1]), y: home.center.y + CGFloat(parts[2])))
        free = g.viewport.clamped(camera)
    }
    #endif
}
