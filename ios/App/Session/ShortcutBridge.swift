import ActivityKit
import Foundation
import PaplyKit
import UIKit

/// Schnelltaste im App-Prozess. Hypothese (Phase 0): Läuft die Sitzung schon, startet die
/// Schnelltaste keine neue Mikro-Aufnahme, sondern markiert nur einen Bereich im laufenden
/// Strom – das sollte auch im Hintergrund gehen.
/// Ergebnis: Zwischenablage + `pending-text.json` (wartet auf 🌐).
@MainActor
enum ShortcutBridge {
    /// Nur die ID merken: Activity ist nicht Sendable und wird je Aufruf frisch geholt.
    private static var activityID: String?

    static func toggle(trigger: String) async -> ShortcutOutcome {
        let session = SessionController.shared
        Diag.log("shortcut.toggle", [
            "trigger": .s(trigger),
            "status": .s(session.status.rawValue),
            "active": .opt(session.active?.source.rawValue),
            "app": .s(SessionController.appState),
        ])

        if let active = session.active, active.source == .shortcut {
            session.finishDictation(id: active.id)
            await update(phase: .polishing, startedAt: active.startedAt)
            return .stopped
        }
        if session.active?.source == .keyboard {
            return .failed("In der Tastatur läuft gerade ein Diktat.")
        }
        guard AppSettings.shared.hasAPIKey else {
            return .failed("Bitte zuerst den Groq-Schlüssel in Paply eintragen.")
        }

        let id = UUID().uuidString
        // AudioRecordingIntent verlangt eine laufende Live Activity – deshalb vor dem Mikro.
        startActivity(id: id)

        if session.status != .ready {
            let ok = await session.startSession(trigger: "shortcut-\(trigger)")
            if !ok {
                await end(phase: .failed, note: "Mikro ließ sich nicht starten")
                return .needsForeground(session.detail ?? "Mikro ließ sich nicht starten")
            }
        }
        switch session.beginDictation(id: id, source: .shortcut) {
        case .started:
            return .started
        case .noAPIKey:
            await end(phase: .failed, note: "Kein Groq-Schlüssel")
            return .failed("Bitte zuerst den Groq-Schlüssel in Paply eintragen.")
        case .notReady:
            await end(phase: .failed, note: "Mikro nicht bereit")
            return .needsForeground("Mikro nicht bereit")
        }
    }

    static func toggleInForeground() async {
        let outcome = await toggle(trigger: "foreground")
        Diag.log("shortcut.foreground.outcome", ["outcome": .s(outcome.logName)])
    }

    static func deliver(_ outcome: DictationOutcome, id: String) {
        var note: String
        var copied = false
        if !outcome.text.isEmpty {
            let before = UIPasteboard.general.changeCount
            UIPasteboard.general.string = outcome.text
            copied = UIPasteboard.general.changeCount != before
            SharedStore.write(PendingText(id: id, text: outcome.text, createdAt: Date()), .pendingText)
            note = copied ? "In der Zwischenablage · 🌐 setzt ein" : "Wartet auf 🌐"
        } else if let error = outcome.errorMessage {
            note = error
        } else {
            note = "Nichts verstanden"
        }
        Diag.log("shortcut.deliver", [
            "id": .s(String(id.prefix(8))),
            "textLen": .i(outcome.text.count),
            "noSpeech": .b(outcome.noSpeech),
            "clipboard": .b(copied),
            "app": .s(SessionController.appState),
        ])
        let failed = outcome.errorMessage != nil
        Task { await end(phase: failed ? .failed : .done, note: note) }
    }

    static func dictationCancelled(id: String) {
        Task { await end(phase: .failed, note: "Verworfen") }
    }

    // MARK: Live Activity

    private static func startActivity(id: String) {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard enabled else {
            Diag.log("activity.disabled")
            return
        }
        let state = DictationActivityAttributes.ContentState(phase: .recording, startedAt: Date(), note: nil)
        do {
            let activity = try Activity.request(
                attributes: DictationActivityAttributes(dictationID: id),
                content: ActivityContent(state: state, staleDate: staleDate),
                pushType: nil
            )
            activityID = activity.id
            Diag.log("activity.start", ["app": .s(SessionController.appState)])
        } catch {
            let ns = error as NSError
            Diag.log("activity.start.failed", ["domain": .s(ns.domain), "code": .i(ns.code), "app": .s(SessionController.appState)])
        }
    }

    /// Bleibt eine Activity nach einem Absturz liegen, gilt sie nach 15 Minuten als veraltet.
    private static var staleDate: Date { Date().addingTimeInterval(15 * 60) }

    /// Beim App-Start: Activities eines abgestürzten Vorgängers sofort beenden.
    static func endLeftoverActivities() {
        activityID = nil
        Task.detached {
            let leftovers = Activity<DictationActivityAttributes>.activities
            for activity in leftovers {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            if !leftovers.isEmpty { Diag.log("activity.leftover.ended", ["count": .i(leftovers.count)]) }
        }
    }

    private static func update(phase: DictationActivityAttributes.ContentState.Phase, startedAt: Date) async {
        guard let id = activityID else { return }
        let state = DictationActivityAttributes.ContentState(phase: phase, startedAt: startedAt, note: nil)
        let stale = staleDate
        await Task.detached {
            guard let activity = Activity<DictationActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: stale))
        }.value
    }

    private static func end(phase: DictationActivityAttributes.ContentState.Phase, note: String) async {
        guard let id = activityID else { return }
        activityID = nil
        let state = DictationActivityAttributes.ContentState(phase: phase, startedAt: Date(), note: note)
        await Task.detached {
            guard let activity = Activity<DictationActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4)))
        }.value
        Diag.log("activity.end", ["phase": .s(phase.rawValue)])
    }
}
