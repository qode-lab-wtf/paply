import Foundation
import Network
import Observation
import PaplyKit
import UIKit

@MainActor
enum ConversationsEnvironment {
    static let root = ThoughtsEnvironment.root.deletingLastPathComponent().appendingPathComponent("Gespraeche")
    static let store = ConversationStore(root: root)
    static let profiles = VoiceProfileStore(root: root)
    static let ledger = ConversationLedger.make(root: root)
    static let editing: any ConversationEditing = EditingPlaceholder()
    static func makeDiarizer() -> any SpeakerDiarizing { SingleSpeakerFallback() }
    static let processor = ConversationProcessor(
        store: store, thoughts: ThoughtsEnvironment.store, profiles: profiles,
        analyzer: ConversationAnalyzer(diarizer: makeDiarizer(), ledger: ledger), environment: processorEnvironment)
    private static var processorEnvironment: ConversationProcessor.Environment {
        .init(
            apiKey: { await MainActor.run { AppSettings.shared.apiKey ?? "" } },
            mainLanguage: { await MainActor.run { AppSettings.shared.effectivePrimaryLanguage ?? "de" } },
            vocabulary: {
                let own = await MainActor.run { AppSettings.shared.effectivePaply.vocabulary }
                let names = (try? await profiles.people().map(\.name)) ?? []
                let topics = await ThoughtsEnvironment.store.topics().map(\.title)
                return [own] + names + topics
            })
    }
    private static var started = false
    private static var observers: [NSObjectProtocol] = []
    private static let network = NWPathMonitor()
    private static var ready: Task<Void, Never>?

    static func bootstrap() {
        guard !started else { return }
        started = true
        ConversationCapture.shared.onRecordingFinished = { item in
            if item.origin == .recording { AppSettings.shared.conversationRecordingCount += 1 }
            await run()
        }
        ConversationBackground.shared.resumePending = { await run() }
        ConversationBackground.shared.onExpiration = { _ in Task { await processor.cancelRunning() } }
        network.pathUpdateHandler = { path in
            if path.status == .satisfied { Task { @MainActor in await run() } }
        }
        network.start(queue: DispatchQueue(label: "paply.conversations.network"))
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in await run() }
            })
        observeKey()
        observePriority()
        Task {
            for await _ in ThoughtsEnvironment.processor.events { await learnWhenIdle() }
        }
        ProtectedData.whenReadable { _ in
            ready = Task {
                await ThoughtsEnvironment.store.setAudioReleaseHook(profiles.learningHook())
                do { try await processor.housekeeping() } catch { Diag.log("conversation.housekeeping.failed") }
            }
            Task { await run() }
        }
        Task {
            for await event in processor.events {
                switch event {
                case .progress(let id, let progress):
                    let stages = ConversationStage.allCases
                    let index = stages.firstIndex(of: progress.stage) ?? 0
                    ConversationBackground.shared.begin(id: id)
                    ConversationBackground.shared.progress(
                        id: id, fraction: (Double(index) + (progress.fraction ?? 0)) / 3)
                    let text = ["Wer spricht …", "Text …", "Zusammenfassung …"][index]
                    ConversationCapture.shared.updateProcessing(id: id, phase: .processing, stage: text)
                    Diag.log("conversation.stage", ["stage": .i(index)])
                case .changed(let id), .failed(let id, _):
                    if let item = try? await store.conversation(id) {
                        let count = await ThoughtsEnvironment.store.thought(id)?.tasks.count ?? 0
                        ConversationCapture.shared.updateProcessing(
                            id: id,
                            phase: item.state == .done ? .done : item.state == .needsAttention ? .failed : .waiting,
                            note: item.state == .done ? "Fertig · \(count) Aufgaben" : nil)
                        ConversationBackground.shared.end(id: id, success: item.state == .done)
                        if [.captured, .waitingNetwork, .waitingLimit, .waitingBudget].contains(item.state) {
                            ConversationBackground.shared.schedule()
                        }
                    }
                }
            }
        }
    }

    static func run() async {
        guard let ready else { return }
        await ready.value
        guard !Task.isCancelled else { return }
        await processor.kick()
        await processor.waitUntilIdle()
        await ConversationsModel.shared.reload()
        await learnWhenIdle()
    }

    private static var learning: Task<Void, Never>?
    private static func observePriority() {
        withObservationTracking {
            _ = SessionController.shared.active
            _ = SessionController.shared.processingCount
            _ = ThoughtCapture.shared.active
            _ = ConversationCapture.shared.active
        } onChange: {
            Task { @MainActor in
                learning?.cancel()
                observePriority()
                await learnWhenIdle()
            }
        }
    }
    private static func learnWhenIdle() async {
        // Der Rückfall darf die begrenzte Warteschlange nicht ohne Lernergebnis leeren.
        let diarizer = makeDiarizer()
        guard diarizer.embeddingModel != "fallback-vad-no-voiceprint", learning == nil,
            !ThoughtsEnvironment.isDictationBusy(), !SessionController.shared.isThoughtActive,
            !SessionController.shared.isConversationActive, !ConversationBackground.shared.isRunning
        else { return }
        learning = Task(priority: .background) {
            await ThoughtsEnvironment.processor.waitUntilIdle()
            if !Task.isCancelled {
                do { try await profiles.processLearningQueue(diarizer: diarizer) } catch {
                    Diag.log("conversation.learning.stopped")
                }
            }
            learning = nil
            await ConversationsModel.shared.reload()
        }
    }

    private static func observeKey() {
        withObservationTracking {
            _ = AppSettings.shared.apiKeySuffix
            _ = AppSettings.shared.hasAPIKey
        } onChange: {
            Task { @MainActor in
                observeKey()
                await run()
            }
        }
    }
}

/// EHRLICHER RÜCKFALL: Sprachpausen, aber keine Sprechertrennung und keine Stimmerkennung.
private struct SingleSpeakerFallback: SpeakerDiarizing {
    let embeddingModel = "fallback-vad-no-voiceprint"
    func voiceprint(audio: URL) async throws -> VoicePrint? { nil }
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws
        -> Diarization
    {
        let work = Task.detached(priority: .utility) { try SpeechRegions.read(audio) }
        let regions = try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
        try Task.checkCancellation()
        progress(1)
        return Diarization(
            segments: regions.map { .init(start: $0.lowerBound, end: $0.upperBound, cluster: 0) },
            centroids: [:], speechSeconds: [0: regions.reduce(0) { $0 + $1.upperBound - $1.lowerBound }],
            model: embeddingModel)
    }
}
