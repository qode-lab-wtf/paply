import ActivityKit
import AudioToolbox
import Observation
import PaplyKit
import UIKit
import WidgetKit

@MainActor @Observable
final class ConversationNavigation {
    static let shared = ConversationNavigation()
    var requestedID: String?
    var showCurrent = false
    var error: String?
}

/// Eintrag und WAV sind fertig, bevor das Mikro angefragt wird.
@MainActor @Observable
final class ConversationCapture {
    static let shared = ConversationCapture()
    struct Active: Equatable {
        var id: String
        var startedAt: Date
        var paused = false
    }
    private(set) var active: Active?
    private(set) var notice: String?
    @ObservationIgnored var store: any ConversationRecordingStore = ConversationRecordingBridge(store: ConversationsEnvironment.store, thoughts: ThoughtsEnvironment.store)
    /// Leitung verdrahtet hier die Auswertung; bis zur Rückkehr bleibt die Sitzung gehalten.
    @ObservationIgnored var onRecordingFinished: (@MainActor (Conversation) async -> Void)?
    @ObservationIgnored private var sink: ConversationAudioSink?
    @ObservationIgnored private var writer: WAVWriter?
    @ObservationIgnored private var activity: Activity<ConversationActivityAttributes>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var finishing = false
    @ObservationIgnored private var pendingDiscard: Bool?
    @ObservationIgnored private var pauseAt: Date?
    @ObservationIgnored private var gapPosition: Double = 0
    @ObservationIgnored private var gaps: [ConversationGap] = []
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var lastCommand: UUID?
    private var manualPause = false
    private var interrupted = false
    private var gapReason = "call"
    var elapsed: Double { Double(writer?.durationMs ?? 0) / 1000 }
    var level: Float { sink?.level ?? 0 }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        let leftovers = Activity<ConversationActivityAttributes>.activities
        Task { for old in leftovers { await old.end(nil, dismissalPolicy: .immediate) } }
        publish()
        ConversationBackground.shared.bootstrap()
        DarwinBus.shared.observe(.conversationToggle) {
            guard let command = SharedStore.read(ConversationCommand.self, .conversationCommand),
                  command.sequence != self.lastCommand else { return }
            self.lastCommand = command.sequence
            Task {
                if let id = command.finishID {
                    if self.active?.id == id {
                        if let paused = command.paused { self.setPaused(paused) } else { self.finish() }
                    }
                } else { _ = await self.toggle(trigger: .control) }
            }
        }
    }

    /// false: Mikro braucht den Vordergrund; Speicherfehler werden als Hinweis sichtbar.
    func toggle(trigger: ThoughtTrigger = .app) async -> Bool {
        ConversationModels.shared.start()
        bootstrap()
        if active != nil { finish(); return true }
        guard !starting, !finishing else { return true }
        notice = nil
        guard ProtectedData.isReadable, freeBytes >= 500_000_000 else {
            notice = "Zum Aufnehmen brauchst du 500 MB freien Speicher und ein entsperrtes iPhone."
            return true
        }
        guard AppSettings.shared.betaConversations else {
            notice = "Aktiviere Gespräche in den Beta-Einstellungen."
            ConversationNavigation.shared.error = notice
            return true
        }
        starting = true
        pendingDiscard = nil
        defer { starting = false }
        do {
            let prepared = try await store.beginRecording(trigger: trigger, at: Date())
            writer = prepared.audio
            gaps = []
            manualPause = false
            interrupted = false
            pauseAt = nil
            active = Active(id: prepared.conversation.id, startedAt: prepared.conversation.createdAt)
            startActivity()
            let file = prepared.audio
            let receiver = ConversationAudioSink(writer: file)
            sink = receiver
            let attached = await SessionController.shared.attachConversation(id: prepared.conversation.id) { receiver.append($0) }
            guard attached else {
                _ = file.close()
                await store.discardRecording(prepared.conversation.id)
                active = nil
                writer = nil
                sink = nil
                endActivity()
                self.activity = nil
                publish()
                return pendingDiscard != nil
            }
            if SessionController.shared.status != .interrupted { resume() }
            publish()
            update(active?.paused == true ? .paused : .recording, alert: "Gespräch läuft")
            startTicker()
            if let discard = pendingDiscard {
                starting = false
                finish(discard: discard)
            }
            return true
        } catch {
            notice = "Das Gespräch konnte nicht starten."
            Diag.log("conversation.start.failed", ["code": .i((error as NSError).code)])
            return true
        }
    }

    func finish(discard: Bool = false) {
        if starting { pendingDiscard = (pendingDiscard ?? false) || discard; return }
        guard let current = active, let file = writer, !finishing else { return }
        finishing = true
        ticker?.cancel()
        closeGap()
        ConversationBackground.shared.begin(id: current.id)
        SessionController.shared.detachConversation(id: current.id)
        let duration = file.close()
        active = nil
        writer = nil
        sink = nil
        publish()
        update(.processing)
        let savedGaps = gaps
        Task {
            defer {
                ConversationBackground.shared.end(id: current.id)
            }
            if discard {
                await store.discardRecording(current.id)
                finishing = false
                endActivity()
                self.activity = nil
                return
            }
            do {
                if let value = try await store.finishRecording(current.id, durationMs: duration, gaps: savedGaps) {
                    finishing = false
                    if let onRecordingFinished { await onRecordingFinished(value) }
                    else { updateProcessing(id: current.id, phase: .waiting) }
                } else {
                    finishing = false
                }
            } catch {
                finishing = false
                updateProcessing(id: current.id, phase: .failed)
                Diag.log("conversation.finish.failed", ["code": .i((error as NSError).code)])
            }
        }
    }
    func discard() { finish(discard: true) }

    func setPaused(_ paused: Bool) {
        guard active != nil, !finishing else { return }
        manualPause = paused
        reconcilePause()
    }
    func pause(needsTap: Bool = false) {
        interrupted = true
        reconcilePause()
        if needsTap { update(.paused, note: "Pausiert – zum Fortsetzen tippen") }
    }
    func resume() {
        interrupted = false
        reconcilePause()
    }
    private func reconcilePause() {
        guard active != nil else { return }
        let shouldPause = manualPause || interrupted
        let reason = interrupted ? "call" : "pause"
        if shouldPause {
            if pauseAt != nil && gapReason != reason { closeGap() }
            if pauseAt == nil {
                gapPosition = sink?.pause() ?? elapsed
                pauseAt = Date()
                gapReason = reason
            }
        } else {
            closeGap()
            sink?.resume()
        }
        active?.paused = shouldPause
        update(shouldPause ? .paused : .recording)
    }
    private func closeGap() {
        if let pauseAt {
            let end = Date()
            gaps.append(ConversationGap(at: gapPosition, seconds: end.timeIntervalSince(pauseAt),
                reason: gapReason, startedAt: pauseAt, endedAt: end))
        }
        pauseAt = nil
    }
    func importAudio(_ url: URL) async {
        guard AppSettings.shared.betaConversations else {
            ConversationNavigation.shared.error = "Aktiviere Gespräche in den Beta-Einstellungen."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let value = try await store.importAudio(from: url, at: Date())
            let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox").standardizedFileURL
            if url.standardizedFileURL.deletingLastPathComponent() == inbox { try? FileManager.default.removeItem(at: url) }
            ConversationNavigation.shared.requestedID = value.id
            ConversationBackground.shared.begin(id: value.id)
            await onRecordingFinished?(value)
            ConversationBackground.shared.end(id: value.id)
        } catch {
            ConversationNavigation.shared.error = "Die Aufnahme ließ sich nicht öffnen."
            Diag.log("conversation.import.failed", ["code": .i((error as NSError).code)])
        }
    }
    private var freeBytes: Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
    private func startTicker() {
        ticker?.cancel()
        ticker = Task {
            var warnedWall = false
            var warnedTwo = false
            var warnedLimit = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let active else { return }
                let seconds = elapsed
                let wallSeconds = Date().timeIntervalSince(active.startedAt)
                if seconds >= 14_400 || wallSeconds >= 28_800 || freeBytes < 200_000_000 || writer?.hasFailed == true {
                    notice = wallSeconds >= 28_800 ? "Acht Stunden – Gespräch gesichert." : seconds >= 14_400 ? "Vier Stunden – Gespräch gesichert." : "Speicher knapp – Gespräch gesichert."
                    finish()
                    return
                }
                if wallSeconds >= 28_500, !warnedWall {
                    warnedWall = true
                    update(active.paused ? .paused : .recording, alert: "Noch 5 Min. bis zum Ende der Aufnahme.")
                }
                if seconds >= 14_100, !warnedLimit {
                    warnedLimit = true
                    update(active.paused ? .paused : .recording, alert: "Noch 5 Min.")
                } else if seconds >= 7_200, !warnedTwo {
                    warnedTwo = true
                    update(active.paused ? .paused : .recording, alert: "Dein Gespräch läuft seit zwei Stunden.")
                }
            }
        }
    }
    private func publish() {
        SharedStore.write(ConversationStateFile(recording: active != nil, id: active?.id), .conversationState)
        ControlCenter.shared.reloadControls(ofKind: "conversation-toggle")
    }
    private func endActivity() {
        guard let id = activity?.id else { return }
        activity = nil
        Task.detached {
            guard let value = Activity<ConversationActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await value.end(nil, dismissalPolicy: .immediate)
        }
    }
    private func startActivity() {
        endActivity()
        guard let active else { return }
        activity = try? Activity.request(attributes: ConversationActivityAttributes(conversationID: active.id),
            content: ActivityContent(state: .init(phase: .recording, startedAt: active.startedAt), staleDate: nil))
    }
    func updateProcessing(id: String, phase: ConversationActivityAttributes.ContentState.Phase, stage: String? = nil, note: String? = nil) {
        guard activity?.attributes.conversationID == id, active == nil else { return }
        update(phase, stage: stage, note: note)
    }
    func update(_ phase: ConversationActivityAttributes.ContentState.Phase, stage: String? = nil, note: String? = nil, alert: String? = nil) {
        if let alert {
            notice = alert
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        }
        guard let activity else { return }
        var state = activity.content.state
        state.phase = phase
        state.stage = stage
        state.note = note ?? alert
        state.elapsed = elapsed
        state.pausedAt = pauseAt
        if active != nil { state.startedAt = Date().addingTimeInterval(-elapsed) }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil),
                alertConfiguration: alert.map { AlertConfiguration(title: "Paply-Gespräch", body: LocalizedStringResource(stringLiteral: $0), sound: .default) })
        }
    }
}
