import AppIntents
import Foundation
#if PAPLY_APP
import PaplyKit
#endif

// Gedanken-Knopf (KONZEPT §3.6, §5): Sperrbildschirm/Kontrollzentrum/Aktionstaste (Control),
// Sperrbildschirm-Widget (Reihe unter der Uhr), Siri und Kurzbefehle. Liegt in App und
// Widget-Erweiterung (Control und Widget brauchen die Typen).
// `LiveActivityIntent` lässt `perform()` im App-Prozess laufen; landet es doch in der Erweiterung,
// leitet die Erweiterung per Darwin an die App weiter. Antworten ohne Dialog (sonst spricht Siri
// in die Aufnahme).

/// Siri, Kurzbefehle, Aktionstaste über Kurzbefehl: Gedanke an/aus.
struct ToggleThoughtIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Gedanke an/aus" }
    static var description: IntentDescription {
        IntentDescription("Ein Aufruf nimmt einen Gedanken auf, der nächste beendet ihn. Paply ordnet ihn in der App.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        let result = await ThoughtIntentRunner.toggle(trigger: "shortcut", intent: "toggle")
        #if PAPLY_APP
        if case .needsForeground = result {
            try await requestToContinueInForeground("Paply öffnet kurz das Mikro.") {
                await ThoughtBridge.startInForeground(trigger: .shortcut)
            }
            return .result()
        }
        #endif
        try result.check()
        return .result()
    }
}

/// Aktion des Steuerelements (ControlWidgetToggle). Der übergebene Wert wird ignoriert: Es zählt
/// der echte Zustand, damit ein veralteter Control-Zustand nie eine zweite Aufnahme startet.
struct SetThoughtRecordingIntent: SetValueIntent, AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Gedanke" }

    @Parameter(title: "Aufnahme")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let result = await ThoughtIntentRunner.toggle(trigger: "control", intent: "control")
        #if PAPLY_APP
        if case .needsForeground = result {
            try await requestToContinueInForeground("Paply öffnet kurz das Mikro.") {
                await ThoughtBridge.startInForeground(trigger: .control)
            }
            return .result()
        }
        #endif
        try result.check()
        return .result()
    }
}

/// Sperrbildschirm-Widget „Paply-Gedanke“: wie das Steuerelement – ein Tipp nimmt auf, der nächste
/// beendet, ohne die App zu öffnen. Zählt als Knopf (`control`), damit die Einrichtung es erkennt.
/// Reagiert die App nicht, öffnet der Tipp Paply (große Ansicht) – ein Widget-Knopf zeigt keine Fehler.
struct ThoughtWidgetIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Gedanke" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        let result = await ThoughtIntentRunner.toggle(trigger: "control", intent: "widget")
        #if PAPLY_APP
        if case .needsForeground = result {
            try await requestToContinueInForeground("Paply öffnet kurz das Mikro.") {
                await ThoughtBridge.startInForeground(trigger: .control)
            }
            return .result()
        }
        #else
        // Widget-Prozess, die App hat nicht reagiert (nicht bereit oder nicht wach). Ein Fehler bliebe beim
        // Widget-Knopf unsichtbar – es passierte einfach nichts. Deshalb Paply öffnen: Die große Ansicht nimmt auf,
        // läuft schon eine Aufnahme, zeigt sie die. `result(opensIntent:)` mit gleichem Ergebnistyp gibt es ab
        // iOS 18.2; unter 18.0/18.1 bleibt es beim Fehler.
        if !result.isOK, #available(iOS 18.2, *), let url = PaplyURL.thoughtStart(source: "widget") {
            Diag.log("thought.intent.widget.openApp")
            return .result(opensIntent: OpenURLIntent(url))
        }
        #endif
        try result.check()
        return .result()
    }
}

/// „Fertig“ in der Live Activity. Passt die ID nicht (veraltete Activity), endet nur diese Activity.
struct FinishThoughtIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Gedanke fertig" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Gedanke")
    var thoughtID: String

    init() {}

    init(thoughtID: String) {
        self.thoughtID = thoughtID
    }

    func perform() async throws -> some IntentResult {
        await ThoughtIntentRunner.finish(id: thoughtID)
        return .result()
    }
}

/// „Verwerfen“ in der Live Activity: Aufnahme stoppen, kein weiterer Upload, keine Strukturierung
/// (schon während der Aufnahme verschickte Stücke lassen sich nicht zurückholen). Der Gedanke landet
/// in „Zuletzt gelöscht“ (wiederherstellbar); kein Bestätigungsdialog (geht in der Activity nicht).
struct DiscardThoughtIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Gedanke verwerfen" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Gedanke")
    var thoughtID: String

    init() {}

    init(thoughtID: String) {
        self.thoughtID = thoughtID
    }

    func perform() async throws -> some IntentResult {
        await ThoughtIntentRunner.discard(id: thoughtID)
        return .result()
    }
}

#if PAPLY_APP
// Nur im App-Prozess: als Ausweg (Fall B gescheitert) die App kurz nach vorne holen.
extension ToggleThoughtIntent: ForegroundContinuableIntent {}
extension SetThoughtRecordingIntent: ForegroundContinuableIntent {}
extension ThoughtWidgetIntent: ForegroundContinuableIntent {}
#endif

enum ThoughtIntentError: Error, CustomLocalizedStringResourceConvertible {
    case refused(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .refused(let message): "\(message)"
        }
    }
}

/// `thought-command.json` – Gedanken-Knopf aus dem Widget-Prozess.
struct ThoughtCommand: Codable, Sendable {
    enum Action: String, Codable, Sendable { case toggle, finish, discard }
    var seq: UInt64
    var action: Action
    var trigger: String
    var thoughtID: String?
}

/// Gemeinsamer Ablauf der Intents – protokolliert immer den Prozess (Spike S1).
enum ThoughtIntentRunner {
    enum Result: Sendable {
        case ok
        case refused(String)
        case needsForeground(String)

        /// Die App hat den Knopf übernommen.
        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }

        /// Abgelehnt → Fehlertext (Siri/Kurzbefehl zeigt ihn); sonst nichts.
        func check() throws {
            switch self {
            case .ok: break
            case .refused(let message): throw ThoughtIntentError.refused(message)
            case .needsForeground: throw ThoughtIntentError.refused("Paply ist gerade nicht bereit. Öffne Paply einmal.")
            }
        }
    }

    /// `trigger` = ThoughtTrigger.rawValue (die Widget-Erweiterung kennt PaplyKit nicht)
    static func toggle(trigger: String, intent: String) async -> Result {
        let started = MonoClock.now()
        Diag.log("thought.intent", [
            "intent": .s(intent),
            "process": .s(PaplyProcess.current.rawValue),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: started)),
        ])
        #if PAPLY_APP
        switch await ThoughtBridge.toggle(trigger: ThoughtTrigger(rawValue: trigger) ?? .unknown) {
        case .started, .stopped, .ignored:
            return .ok
        case .refused(let message):
            return .refused(message)
        case .needsForeground(let reason):
            Diag.log("thought.foreground.request", ["reason": .s(reason)])
            return .needsForeground(reason)
        }
        #else
        // Widget-Prozess: weiterleiten und kurz prüfen, ob die App reagiert (Aufnahme-Zustand wechselt)
        let before = SharedStore.read(ThoughtStateFile.self, .thoughtState)?.recording ?? false
        forward(.toggle, trigger: trigger, id: nil)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if (SharedStore.read(ThoughtStateFile.self, .thoughtState)?.recording ?? false) != before { return .ok }
        }
        Diag.log("thought.intent.forward.timeout")
        return .refused("Paply ist gerade nicht bereit. Öffne Paply einmal, dann klappt der Knopf.")
        #endif
    }

    static func finish(id: String) async {
        Diag.log("thought.intent", ["intent": .s("finish"), "process": .s(PaplyProcess.current.rawValue), "id": .s(String(id.prefix(8)))])
        #if PAPLY_APP
        await ThoughtBridge.finishFromActivity(id: id)
        #else
        forward(.finish, trigger: "liveActivity", id: id)
        #endif
    }

    static func discard(id: String) async {
        Diag.log("thought.intent", ["intent": .s("discard"), "process": .s(PaplyProcess.current.rawValue), "id": .s(String(id.prefix(8)))])
        #if PAPLY_APP
        await ThoughtBridge.discardFromActivity(id: id)
        #else
        forward(.discard, trigger: "liveActivity", id: id)
        #endif
    }

    /// Widget-Prozess → App: Befehl in die App Group, Darwin-Signal. Die App ist (Fall A) wach.
    private static func forward(_ action: ThoughtCommand.Action, trigger: String, id: String?) {
        let seq = MonoClock.now()
        let written = SharedStore.write(ThoughtCommand(seq: seq, action: action, trigger: trigger, thoughtID: id), .thoughtCommand)
        DarwinBus.shared.post(.thoughtToggle)
        Diag.log("thought.intent.forward", ["action": .s(action.rawValue), "written": .b(written)])
    }
}
