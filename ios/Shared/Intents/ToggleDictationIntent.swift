import AppIntents
import Foundation

/// Schnelltaste: Diktat an/aus (Rückseite doppelt tippen über Kurzbefehle, Kontrollzentrum,
/// Aktionstaste). Liegt in App und Widget-Erweiterung, weil das ControlWidget den Typ braucht.
/// `LiveActivityIntent` sorgt laut Praxisberichten dafür, dass `perform()` im App-Prozess
/// läuft (AudioRecordingIntent allein reicht nicht). Welcher Prozess es wirklich ist,
/// wird protokolliert (Phase 0); landet es in der Erweiterung, leitet sie per Darwin weiter.
struct ToggleDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Diktat an/aus" }
    static var description: IntentDescription {
        IntentDescription("Startet ein Diktat mit Paply oder beendet es. Der Text landet in der Zwischenablage und wartet auf 🌐.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        let started = MonoClock.now()
        Diag.log("intent.perform", [
            "process": .s(PaplyProcess.current.rawValue),
            "bundle": .s(Bundle.main.bundleIdentifier ?? "?"),
            "pid": .i(Int(getpid())),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: started)),
        ])
        #if PAPLY_APP
        let outcome = await ShortcutBridge.toggle(trigger: "intent")
        Diag.log("intent.outcome", ["outcome": .s(outcome.logName), "ms": .ms(MonoClock.msSince(started))])
        switch outcome {
        case .started, .stopped:
            break
        case .needsForeground(let reason):
            Diag.log("intent.foreground.request", ["reason": .s(reason)])
            try await requestToContinueInForeground("Paply muss kurz geöffnet werden, um das Mikro einzuschalten.") {
                await ShortcutBridge.toggleInForeground()
            }
        case .failed(let message):
            throw PaplyIntentError.failed(message)
        }
        #else
        let outcome = await ShortcutForwarder.forward()
        Diag.log("intent.forward.outcome", ["outcome": .s(outcome.logName), "ms": .ms(MonoClock.msSince(started))])
        switch outcome {
        case .started, .stopped:
            break
        case .needsForeground:
            throw PaplyIntentError.notRunning
        case .failed(let message):
            throw PaplyIntentError.failed(message)
        }
        #endif
        return .result()
    }
}

#if PAPLY_APP
// Nur im App-Prozess: als Ausweg die App in den Vordergrund holen.
extension ToggleDictationIntent: ForegroundContinuableIntent {}
#endif

enum ShortcutOutcome: Sendable, Equatable {
    case started
    case stopped
    case needsForeground(String)
    case failed(String)

    var logName: String {
        switch self {
        case .started: "started"
        case .stopped: "stopped"
        case .needsForeground: "needsForeground"
        case .failed: "failed"
        }
    }
}

enum PaplyIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "Paply ist gerade nicht bereit. Öffne Paply einmal, dann klappt die Schnelltaste."
        case .failed(let message): "\(message)"
        }
    }
}

/// Widget-Prozess → App: Befehl in die App Group schreiben, Darwin-Signal senden,
/// kurz auf die Bestätigung warten.
enum ShortcutForwarder {
    static func forward(timeout: Duration = .milliseconds(1500)) async -> ShortcutOutcome {
        let seq = MonoClock.now()
        guard SharedStore.write(ShortcutCommand(seq: seq, sentNs: seq), .shortcutCommand) else {
            Diag.log("intent.forward.noAppGroup")
            return .failed("Paply kann nicht auf den gemeinsamen Speicher zugreifen.")
        }
        DarwinBus.shared.post(.shortcut)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            if let ack = SharedStore.read(ShortcutAck.self, .shortcutAck), ack.seq == seq {
                Diag.log("intent.forward.ack", ["outcome": .s(ack.outcome.rawValue), "ms": .ms(MonoClock.ms(from: seq, to: ack.ackNs))])
                switch ack.outcome {
                case .started: return .started
                case .stopped: return .stopped
                case .failed: return .failed(ack.detail ?? "Das hat nicht geklappt.")
                }
            }
        }
        Diag.log("intent.forward.timeout")
        return .needsForeground("Keine Antwort von der App")
    }
}
