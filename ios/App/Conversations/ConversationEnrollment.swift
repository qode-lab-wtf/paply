import Foundation
import Observation
import PaplyKit

@MainActor @Observable
final class ConversationEnrollment {
    private(set) var startedAt: Date?
    private(set) var starting = false
    var error: String?
    var level: Float { sink?.level ?? 0 }
    @ObservationIgnored private var sink: ConversationAudioSink?
    @ObservationIgnored private var writer: WAVWriter?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var id = UUID().uuidString
    @ObservationIgnored private var cancelled = false
    private static var processing = false
    private static var pendingDirectory: URL { ConversationsEnvironment.root.appendingPathComponent("enrollment-pending") }

    func start() async {
        guard startedAt == nil, !starting else { return }
        error = nil
        Diag.log("conversation.enrollment.start")
        guard !SessionController.shared.isConversationActive else {
            error = "Es läuft bereits eine Aufnahme. Beende sie bitte zuerst."
            Diag.log("conversation.enrollment.attach", ["ok": .b(false), "reason": .i(1)])
            return
        }
        ConversationModels.shared.start()
        ConversationsEnvironment.prewarm()
        starting = true
        cancelled = false
        id = UUID().uuidString
        defer { starting = false }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-enroll-\(id).wav")
            let writer = try WAVWriter(url: url)
            self.writer = writer
            let sink = ConversationAudioSink(writer: writer)
            self.sink = sink
            let attached = await SessionController.shared.attachConversation(id: id, sink: { sink.append($0) })
            Diag.log("conversation.enrollment.attach", ["ok": .b(attached), "reason": .i(cancelled ? 2 : attached ? 0 : 3)])
            guard attached, !cancelled else {
                if !cancelled { error = "Das Mikrofon konnte nicht starten. Prüfe den Mikrofonzugriff und versuche es erneut." }
                finish(save: false)
                return
            }
            startedAt = Date()
            timer = Task {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                finish(save: true)
            }
        } catch {
            self.error = "Die Stimmaufnahme konnte nicht gespeichert werden."
            Diag.log("conversation.enrollment.failed", ["code": .i((error as NSError).code)])
            finish(save: false)
        }
    }
    func finish(save: Bool) {
        cancelled = true
        timer?.cancel(); timer = nil
        _ = sink?.pause()
        SessionController.shared.detachConversation(id: id)
        sink = nil
        guard let writer else { return }
        self.writer = nil
        let duration = writer.close()
        Diag.log("conversation.enrollment.recorded", ["ms": .i(duration), "save": .b(save)])
        if save {
            do {
                try FileManager.default.createDirectory(at: Self.pendingDirectory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: writer.url, to: Self.pendingDirectory.appendingPathComponent(id + ".wav"))
                Task { await Self.processPending() }
            } catch {
                self.error = "Die Stimmaufnahme konnte nicht gesichert werden. Bitte erneut versuchen."
            }
        } else { try? FileManager.default.removeItem(at: writer.url) }
        startedAt = nil
    }
    static func processPending() async {
        guard ConversationModels.isReady, !processing else { return }
        processing = true
        defer { processing = false }
        let files = (try? FileManager.default.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "wav" {
            do {
                try await ConversationsEnvironment.profiles.enroll(audio: file, diarizer: ConversationsEnvironment.makeDiarizer())
                try FileManager.default.removeItem(at: file)
                Diag.log("conversation.enrollment.result", ["ok": .b(true)])
            } catch SpeakerProcessingDeferred.thermal { return }
            catch {
                Diag.log("conversation.enrollment.result", ["ok": .b(false), "code": .i((error as NSError).code)])
                ConversationsModel.shared.error = "Die Stimme konnte nicht erkannt werden. Die Aufnahme ist gesichert; bitte erneut versuchen."
                return
            }
        }
        await ConversationsModel.shared.reload()
    }
}
