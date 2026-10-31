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
    static var editing: any ConversationEditing { processor }
    static func makeDiarizer() -> any SpeakerDiarizing { AvailableSpeakerDiarizer() }
    static let processor = ConversationProcessor(
        store: store, thoughts: ThoughtsEnvironment.store, profiles: profiles,
        analyzer: ConversationAnalyzer(diarizer: makeDiarizer(), ledger: ledger), environment: processorEnvironment)
    private static var processorEnvironment: ConversationProcessor.Environment {
        .init(
            apiKey: { await MainActor.run { AppSettings.shared.apiKey ?? "" } },
            mainLanguage: { await MainActor.run { AppSettings.shared.effectivePrimaryLanguage ?? "de" } },
            vocabulary: {
                let own = await MainActor.run { AppSettings.shared.effectivePaply.vocabulary }
                return [own]
            }, userLanguages: { await MainActor.run { AppSettings.shared.effectivePaply.spokenLanguages } })
    }
    // Anschlussstelle für die Bereitschaft des echten Motors.
    static var voiceLearningAllowed: Bool { AppSettings.shared.betaConversations }
    private static var started = false
    private static var observers: [NSObjectProtocol] = []
    private static let network = NWPathMonitor()
    private static var ready: Task<Void, Never>?

    static func bootstrap() {
        guard !started else { return }
        started = true
        Task {
            for await (code, values) in ConversationDiagnostics.events {
                Diag.log(code, values.mapValues { .i($0) })
            }
        }
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
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in Task.detached(priority: .utility) { NemotronSpeakerDiarizer.releaseModels() } })
        ConversationLearning.observe()
        observeKey()
        observePriority()
        Task {
            for await _ in ThoughtsEnvironment.processor.events { await learnWhenIdle() }
        }
        ProtectedData.whenReadable { _ in
            ready = Task {
                await ConversationLearning.refresh()
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
                            note: item.state == .done ? (count == 0 ? "Fertig" : "Fertig · \(count) Aufgaben") : nil)
                        ConversationBackground.shared.end(id: id, success: item.state == .done)
                        if [.captured, .waitingNetwork, .waitingLimit, .waitingBudget].contains(item.state) {
                            ConversationBackground.shared.schedule()
                        }
                    }
                }
            }
        }
    }

    static func prewarm() {
        guard ConversationModels.isReady else { return }
        Task(priority: .background) {
            do { try await NemotronSpeakerDiarizer(directory: ConversationModels.directory).prewarm() }
            catch { Diag.log("conversation.prewarm.failed", ["code": .i((error as NSError).code)]) }
        }
    }
    static func run() async {
        guard let ready else { return }
        await ready.value
        guard !Task.isCancelled else { return }
        await ConversationEnrollment.processPending()
        await processor.kick()
        await processor.waitUntilIdle()
        await ConversationLearning.refresh()
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
        guard voiceLearningAllowed, ConversationModels.isReady, learning == nil,
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

/// Prüft den Modellstand bei jedem Lauf; fehlende Modelle lassen die Sprecherstufe offen.
private struct AvailableSpeakerDiarizer: SpeakerDiarizing {
    var embeddingModel: String { CAMVoiceEmbedding.modelID }
    func voiceprint(audio: URL) async throws -> VoicePrint? {
        guard ConversationModels.isReady else { throw ThoughtStoreError.unavailable }
        return try await NemotronSpeakerDiarizer(directory: ConversationModels.directory).voiceprint(audio: audio)
    }
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        guard ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { throw SpeakerProcessingDeferred.thermal }
        guard ConversationModels.isReady else { throw ThoughtStoreError.unavailable }
        do {
            return try await NemotronSpeakerDiarizer(directory: ConversationModels.directory)
                .diarize(audio: audio, expectedSpeakers: expectedSpeakers, progress: progress)
        } catch SpeakerProcessingDeferred.thermal { throw SpeakerProcessingDeferred.thermal }
        catch is CancellationError { throw CancellationError() }
        catch {
            Diag.log("conversation.diarizer.failed", ["code": .i((error as NSError).code)])
            throw error
        }
    }
}
