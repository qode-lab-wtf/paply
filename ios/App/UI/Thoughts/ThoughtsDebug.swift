#if DEBUG
import PaplyKit
import SwiftUI

// Nur im Debug: Vorschaudaten und Bildschirmfotos ohne Antippen (Simulator).
//   -PaplyPreviewData        ThoughtsModel.preview (60 Gedanken, 8 Themen, alle Zustände) + gespielte Aufnahme
//   -PaplyEmpty              leeres Modell (leerer Zustand)
//   -PaplyMany               2 000 Gedanken (Scrollen, Abschnitte)
//   -PaplyScreen <name>      overview · topic · tasks · detail · detail-raw · detail-waiting · capture ·
//                            bar · bar-saved · search · settings · dictation · deleted · topics · guide · picker
//   -PaplyClassic            iOS-18-Look (ohne Glas, Leiste als Kapsel) auf iOS 26
//   -PaplyExpandOriginal     „Original“ im Detail aufgeklappt
//   -PaplyHoldDone           große Ansicht bleibt nach „Fertig“ offen (Häkchen prüfen)
//   -PaplyRefuse             gespielte Aufnahme wird abgelehnt (Fehlerzustand)
enum ThoughtsDebug {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static var previewData: Bool { args.contains("-PaplyPreviewData") || args.contains("-PaplyMany") }

    static var screen: String? {
        guard let i = args.firstIndex(of: "-PaplyScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func model() -> ThoughtsModel? {
        if args.contains("-PaplyEmpty") { return ThoughtsModel() }
        if args.contains("-PaplyMany") { return many() }
        if args.contains("-PaplyPreviewData") { return ThoughtsModel.preview }
        return nil
    }

    @MainActor
    static func driver(model: ThoughtsModel) -> (any CaptureDriving)? {
        guard previewData || args.contains("-PaplyEmpty") else { return nil }
        return DemoCapture(model: model)
    }

    /// 2 000 Gedanken aus den Vorschaudaten (neue Kennungen, über ~2 Jahre verteilt)
    @MainActor
    private static func many() -> ThoughtsModel {
        let base = ThoughtsModel.preview
        let samples = base.thoughts.filter { $0.state == .done }
        var thoughts: [Thought] = []
        let now = Date()
        for i in 0..<2_000 {
            var t = samples[i % samples.count]
            t.id = ThoughtIDs.thought()
            t.createdAt = now.addingTimeInterval(-Double(i) * 31_000)
            t.tasks = t.tasks.map { var k = $0; k.id = ThoughtIDs.task(); return k }
            t.links = []
            thoughts.append(t)
        }
        return ThoughtsModel(thoughts: thoughts, topics: base.topics, suggestions: base.suggestions)
    }

    /// Stellt den gewünschten Bildschirm her (einmal beim Start)
    @MainActor
    static func apply(nav: ThoughtsNav, flow: CaptureFlow, model: ThoughtsModel) async {
        guard let screen else { return }
        try? await Task.sleep(for: .milliseconds(400))
        let rich = model.thoughts.first { $0.state == .done && !$0.tasks.isEmpty && !$0.links.isEmpty && !$0.textIsRaw }
            ?? model.thoughts.first { $0.state == .done }
        switch screen {
        case "topic":
            // aktives Thema mit offenen Aufgaben
            let topic = model.topics.filter { model.isActive($0) }
                .max { model.openTasks(topicID: $0.id).count < model.openTasks(topicID: $1.id).count }
            if let id = topic?.id ?? rich?.topicId { nav.filter = .topic(id) }
        case "tasks":
            nav.filter = .tasks
        case "detail":
            if let rich { nav.path = [.thought(rich.id)] }
        case "detail-raw":
            if let raw = model.thoughts.first(where: { $0.textIsRaw }) { nav.path = [.thought(raw.id)] }
        case "detail-waiting":
            if let waiting = model.thoughts.first(where: { $0.state == .waitingKey }) { nav.path = [.thought(waiting.id)] }
        case "capture":
            flow.openBig()
        case "capture-done":
            flow.openBig()
            try? await Task.sleep(for: .seconds(1.2))
            flow.finishFromBig()
        case "bar":
            // nach der Fall-B-Schonfrist starten, sonst öffnet sich die große Ansicht
            try? await Task.sleep(for: .seconds(3.2))
            _ = await flow.driver.toggle(trigger: .app)
        case "bar-saved":
            if let rich { flow.debugShow(.saved(rich.id)) }
        case "bar-ordering":
            if let first = model.thoughts.first { flow.debugShow(.ordering(first.id)) }
        case "search":
            nav.path = [.search]
            try? await Task.sleep(for: .milliseconds(700))
            nav.searchText = "Porto"
        case "search-empty":
            nav.path = [.search]
        case "settings":
            nav.showSettings = true
        case "dictation":
            nav.tab = .dictation
        case "deleted":
            nav.path = [.deleted]
        case "topics":
            nav.path = [.topics]
        case "guide":
            nav.path = [.buttonGuide]
        case "picker":
            if let rich { nav.topicPicker = SheetID(id: rich.id) }
        default:
            break
        }
    }
}

/// Gespielte Aufnahme für Vorschau und Bildschirmfotos: Pegel wie Sprache, Zeit ab 1:12.
@MainActor
@Observable
final class DemoCapture: CaptureDriving {
    private(set) var active: ThoughtCapture.Active?
    private(set) var lastStop: ThoughtCapture.LastStop?
    private(set) var lastDiscard: ThoughtCapture.LastDiscard?
    @ObservationIgnored private let model: ThoughtsModel
    @ObservationIgnored private var speechTask: Task<Void, Never>?

    init(model: ThoughtsModel) {
        self.model = model
    }

    var level: Float {
        guard active != nil else { return 0 }
        let t = Date().timeIntervalSinceReferenceDate
        // Silben (≈ 5 Hz) in Wörtern (≈ 0,7 Hz), dazwischen kurze Pausen
        let syllables = max(0, sin(t * 2 * .pi * 4.7))
        let words = max(0, sin(t * 2 * .pi * 0.7) + 0.35)
        return Float(min(1, syllables * words * 0.85 + 0.05))
    }

    func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome {
        if ProcessInfo.processInfo.arguments.contains("-PaplyRefuse") {
            try? await Task.sleep(for: .milliseconds(400))
            return .refused("Diktat läuft gerade")
        }
        if let active {
            finish(.app)
            return .stopped(active.id)
        }
        try? await Task.sleep(for: .milliseconds(250))
        let id = model.thoughts.first { $0.isProcessing }?.id ?? ThoughtIDs.thought()
        active = ThoughtCapture.Active(id: id, startedAt: Date().addingTimeInterval(-72), speechDetected: false)
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard let self, let current = self.active else { return }
            self.active = ThoughtCapture.Active(id: current.id, startedAt: current.startedAt, speechDetected: true)
        }
        return .started(id)
    }

    func finish(_ reason: ThoughtFinishReason) {
        speechTask?.cancel()
        if let active { lastStop = ThoughtCapture.LastStop(id: active.id, reason: reason, at: Date()) }
        active = nil
    }

    func discard() {
        speechTask?.cancel()
        if let active { lastDiscard = ThoughtCapture.LastDiscard(id: active.id, at: Date()) }
        active = nil
    }
}
#endif
