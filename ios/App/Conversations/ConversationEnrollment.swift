import Foundation
import Observation
import PaplyKit

@MainActor @Observable
final class ConversationEnrollment {
    private(set) var startedAt: Date?
    private(set) var starting = false
    var level: Float { sink?.level ?? 0 }
    @ObservationIgnored private var sink: ConversationAudioSink?
    @ObservationIgnored private var writer: WAVWriter?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var id = UUID().uuidString
    @ObservationIgnored private var cancelled = false
    func start() async {
        ConversationModels.shared.start()
        guard startedAt == nil, !starting, !SessionController.shared.isConversationActive else { return }
        starting = true
        cancelled = false
        defer { starting = false }
        ConversationsModel.shared.stopPlayback()
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-enroll-\(id).wav")
            let writer = try WAVWriter(url: url)
            self.writer = writer
            let sink = ConversationAudioSink(writer: writer)
            self.sink = sink
            guard await SessionController.shared.attachConversation(id: id, sink: { sink.append($0) }), !cancelled
            else {
                finish(save: false)
                return
            }
            startedAt = Date()
            timer = Task {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                finish(save: true)
            }
        } catch { finish(save: false) }
    }
    func finish(save: Bool) {
        cancelled = true
        timer?.cancel()
        timer = nil
        _ = sink?.pause()
        SessionController.shared.detachConversation(id: id)
        startedAt = nil
        sink = nil
        guard let writer else { return }
        self.writer = nil
        Task {
            _ = writer.close()
            defer { try? FileManager.default.removeItem(at: writer.url) }
            if save {
                do {
                    try await ConversationsEnvironment.profiles.enroll(
                        audio: writer.url, diarizer: ConversationsEnvironment.makeDiarizer())
                } catch { ConversationsModel.shared.error = "Die Stimme konnte nicht eindeutig erkannt werden. Bitte erneut einsprechen." }
            }
        }
    }
}
