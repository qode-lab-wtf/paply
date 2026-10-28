#if DEBUG
import PaplyKit
import SwiftUI

// Nur im Debug: Vorschaudaten und Bildschirmfotos ohne Antippen (Simulator).
//   -PaplyPreviewData        ThoughtsModel.preview (60 Gedanken, 8 Themen, alle Zustände) + gespielte Aufnahme
//   -PaplyEmpty              leeres Modell (leerer Zustand)
//   -PaplyMany               2 000 Gedanken (Scrollen, Abschnitte)
//   -PaplyCount <n>          n fertige Gedanken in wenigen Themen (1, 5, 300 … – Fälle der Karte)
//   -PaplyTasksDemo          Vorschaudaten mit echt wirkenden Aufgaben in allen Gruppen (überfällig, heute,
//                            demnächst, irgendwann, erledigt – auch ältere)
//   -PaplyTopicImages <…>    Themenbilder einspielen, durch Kommas getrennt: „Titel=Pfad“ oder nur „Pfad“ (dann der
//                            Reihe nach für die Themen mit den meisten Gedanken). Relative Pfade gelten ab dem
//                            Datenordner der App (`xcrun simctl get_app_container … data`).
//   -PaplyScreen <name>      overview · topic · topic-small · topic-large · topic-edit · loose · pending · tasks ·
//                            tasks-done · tasks-all-done · tasks-detail · detail · detail-zoom · detail-raw ·
//                            detail-waiting · capture · bar · bar-saved · search · settings · dictation · deleted ·
//                            topics · guide · picker ·
//                            map (Karte allein, MapDebugScreen; dazu -PaplyMapFocus, -PaplyLight) ·
//                            widgets · widgets-2 (Aufgaben-Widgets, TaskWidgetPreview; mit -PaplyTasksDemo)
//   -PaplyClassic            iOS-18-Look (ohne Glas, Leiste als Kapsel) auf iOS 26
//   -PaplyExpandOriginal     „Original“ im Detail aufgeklappt
//   -PaplyHoldDone           große Ansicht bleibt nach „Fertig“ offen (Häkchen prüfen)
//   -PaplyRefuse             gespielte Aufnahme wird abgelehnt (Fehlerzustand)
enum ThoughtsDebug {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static var previewData: Bool {
        args.contains("-PaplyPreviewData") || args.contains("-PaplyMany") || args.contains("-PaplyTasksDemo") || count != nil
    }

    static var count: Int? {
        guard let i = args.firstIndex(of: "-PaplyCount"), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    static var screen: String? {
        guard let i = args.firstIndex(of: "-PaplyScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func model() -> ThoughtsModel? {
        if args.contains("-PaplyEmpty") { return ThoughtsModel() }
        if args.contains("-PaplyMany") { return many() }
        if let count { return sample(count) }
        if args.contains("-PaplyTasksDemo") { return tasksDemo() }
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

    /// n fertige Gedanken in wenigen Themen: einige Themen mit mehreren, eins mit einem, ein Gedanke ohne Thema
    @MainActor
    private static func sample(_ count: Int) -> ThoughtsModel {
        let base = ThoughtsModel.preview
        let samples = base.thoughts.filter { $0.state == .done && !$0.textIsRaw && $0.topicId != nil }
        let topics = base.topics.filter { base.isActive($0) }
        let pattern = [0, 0, 1, 2, -1, 0, 1, 3, 0, 2, 4, 5, 1, 6, 0, 3, 7]
        var thoughts: [Thought] = []
        let now = Date()
        for i in 0..<max(0, count) {
            var t = samples[i % samples.count]
            t.id = ThoughtIDs.thought()
            let slot = pattern[i % pattern.count]
            t.topicId = slot < 0 ? nil : topics[slot % topics.count].id
            t.createdAt = now.addingTimeInterval(-Double(i) * (count > 40 ? 26_000 : 9_000) - 600)
            t.tasks = t.tasks.map { var k = $0; k.id = ThoughtIDs.task(); return k }
            t.links = []
            if i > 0, i % 5 == 0, let previous = thoughts.last {
                t.links = [ThoughtLink(target: previous.id, kind: .sameMatter, reason: "Gleiches Anliegen", origin: .ai, createdAt: t.createdAt)]
            }
            thoughts.append(t)
        }
        return ThoughtsModel(thoughts: thoughts, topics: base.topics)
    }

    /// Aufgaben wie im Alltag, in allen Gruppen; je an einen passenden Gedanken (frischer Wortlaut nur an Gedanken
    /// von heute, sonst an ältere – so zeigt die Liste beide Fälle der Fälligkeit)
    @MainActor
    private static func tasksDemo() -> ThoughtsModel {
        let base = ThoughtsModel.preview
        var thoughts = base.thoughts.map { thought -> Thought in
            var t = thought
            t.tasks = []
            return t
        }
        let topics = base.topics
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            (calendar.date(byAdding: .day, value: offset, to: today) ?? today).addingTimeInterval(Double(hour * 3_600 + minute * 60))
        }
        /// neuester passender Gedanke des Themas: von heute (`fresh`) bzw. älter als ein Tag
        func index(_ topicTitle: String, fresh: Bool) -> Int? {
            let topicID = topics.first { $0.title == topicTitle }?.id
            let candidates = thoughts.indices.filter { thoughts[$0].topicId == topicID && thoughts[$0].state == .done && !thoughts[$0].textIsRaw }
            return candidates.first { fresh == (thoughts[$0].createdAt >= today) }
                ?? candidates.first { fresh ? true : thoughts[$0].createdAt < day(-1) }
                ?? candidates.first
        }
        typealias Demo = (topic: String, fresh: Bool, text: String, hint: String?, due: Date?, doneAt: Date?)
        let demos: [Demo] = [
            ("Wohnung", false, "Mietvertrag unterschreiben und zurückschicken", "bis Montag", day(-1), nil),
            ("Finanzen", false, "Rechnung vom Zahnarzt überweisen", "Ende der Woche", day(-3), nil),
            ("Finanzen", true, "Steuerberater wegen der Belege anrufen", "heute um 15 Uhr", day(0, 15), nil),
            ("Garten", false, "Tomaten ausgeizen und die Beete gießen", "morgen", day(0), nil),
            ("Team", true, "Notizen aus der Retro an alle schicken", "heute Abend", day(0, 19), nil),
            ("Urlaub Portugal", false, "Flug nach Porto buchen", "Freitag", day(3), nil),
            ("Paply", true, "Testflug-Version an Lena schicken", "morgen", day(1), nil),
            ("Finanzen", false, "Sparplan um fünfzig Euro erhöhen", "ab dem Ersten", day(5), nil),
            ("Urlaub Portugal", false, "Hotel in der Altstadt reservieren", "am 12. Dezember", day(46), nil),
            ("Lesen", false, "Buch über Gewohnheiten in der Bibliothek vormerken", nil, nil, nil),
            ("Ideen", false, "Einkaufsliste nach Laden sortieren – Prototyp skizzieren", nil, nil, nil),
            ("Wohnung", false, "Klausel zur Staffelmiete beim Vermieter nachfragen", nil, nil, nil),
            ("Team", false, "Reviews in der nächsten Runde ansprechen", nil, nil, nil),
            ("Paply", true, "Gedanken-Knopf auf dem Sperrbildschirm ausprobieren", nil, nil, day(0, 9, 12)),
            ("Garten", false, "Neuen Gartenschlauch kaufen", "Samstag", day(-1, 12), day(-1, 17, 40)),
            ("Team", false, "Retro vorbereiten", nil, nil, day(-3, 10)),
            ("Urlaub Portugal", false, "Reisepass verlängern", "nächste Woche", day(-25), day(-20, 11)),
            ("Finanzen", false, "Steuerunterlagen sortieren", nil, nil, day(-40, 18)),
        ]
        for demo in demos {
            guard let i = index(demo.topic, fresh: demo.fresh) else { continue }
            let created = thoughts[i].createdAt
            thoughts[i].tasks.append(ThoughtTask(text: demo.text, quote: demo.text, dueHint: demo.hint, dueAt: demo.due,
                                                 done: demo.doneAt != nil, doneAt: demo.doneAt, owner: .ai, createdAt: created))
        }
        // mit gesprochener Uhrzeit in der Zukunft (Karte „Bei Uhrzeit erinnern?“, TaskReminders)
        if let i = index("Team", fresh: true) {
            thoughts[i].tasks.append(ThoughtTask(text: "Briefe bei Aram bearbeiten", quote: "morgen um 8 Briefe bei Aram bearbeiten",
                                                 dueHint: "morgen um 8", dueAt: day(1, 8), dueHasTime: true, owner: .ai,
                                                 createdAt: thoughts[i].createdAt))
        }
        return ThoughtsModel(thoughts: thoughts + base.deleted, topics: topics, suggestions: base.suggestions)
    }

    /// `-PaplyTopicImages`: Bilder einspielen (wie „Bild wählen …“, gleicher Zuschnitt)
    @MainActor
    private static func applyTopicImages(model: ThoughtsModel) async {
        guard let i = args.firstIndex(of: "-PaplyTopicImages"), i + 1 < args.count else { return }
        let ranked = model.topics.sorted { model.count(of: $0.id) > model.count(of: $1.id) }
        var next = ranked.makeIterator()
        for entry in args[i + 1].split(separator: ",").map(String.init) {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            let topic = parts.count == 2 ? model.topics.first { $0.title == parts[0] } : next.next()
            let path = parts.last ?? entry
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
            guard let topic, let data = try? Data(contentsOf: url), let jpeg = await TopicImages.process(data) else { continue }
            TopicImages.shared.setImage(jpeg, for: topic.id)
        }
    }

    /// Stellt den gewünschten Bildschirm her (einmal beim Start)
    @MainActor
    static func apply(nav: ThoughtsNav, flow: CaptureFlow, model: ThoughtsModel) async {
        await applyTopicImages(model: model)
        guard let screen else { return }
        try? await Task.sleep(for: .milliseconds(400))
        let rich = model.thoughts.first { $0.state == .done && !$0.tasks.isEmpty && !$0.links.isEmpty && !$0.textIsRaw }
            ?? model.thoughts.first { $0.state == .done }
        switch screen {
        case "topic", "topic-small", "topic-large":
            // aktives Thema mit offenen Aufgaben
            let topic = model.topics.filter { model.isActive($0) && model.count(of: $0.id) > 0 }
                .max { model.openTasks(topicID: $0.id).count < model.openTasks(topicID: $1.id).count }
            if let id = topic?.id ?? rich?.topicId { nav.focus(id) }
            if screen == "topic-small" { nav.panelDetent = .small }
            if screen == "topic-large" { nav.panelDetent = .large }
        case "loose":
            nav.focus(ThoughtsHome.noTopicID)
        case "pending":
            nav.focus(ThoughtsHome.pendingID)
        case "tasks", "tasks-done", "tasks-all-done":
            nav.showTasks()
        case "tasks-detail":
            nav.showTasks()
            let agenda = model.taskAgenda()
            if let item = (agenda.today + agenda.overdue + agenda.upcoming + agenda.someday).first {
                try? await Task.sleep(for: .milliseconds(1_500))
                // wie Antippen der Zeile (Zoom aus der Zeile)
                nav.tasksPath.append(.thought(item.thought.id, task: item.task.id, zoom: "task:\(item.id)"))
            }
        case "detail":
            if let rich { nav.path = [.thought(rich.id)] }
        case "detail-zoom":
            // wie aus dem Panel geöffnet (Zoom aus der Karte)
            if let rich, let topic = rich.topicId {
                nav.focus(topic)
                try? await Task.sleep(for: .milliseconds(900))
                nav.path = [.thought(rich.id, zoom: "panel:\(rich.id)")]
            }
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
        case "map":
            MapDebugScreen.present(model: model)
        case "widgets", "widgets-2":
            TaskWidgetPreview.present(model: model, page: screen == "widgets-2" ? 2 : 1)
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
