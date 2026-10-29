import PaplyKit
import SwiftUI

struct ConversationSettingsHost: View {
    @State private var model = ConversationsModel.shared
    @State private var enrollment = ConversationEnrollment()
    @State private var showEnrollment = false
    var body: some View {
        ConversationSettingsSection(
            learnedThoughtCount: model.learnedThoughtCount, people: model.people,
            onEnroll: { showEnrollment = true },
            onForgetOwner: {
                model.perform { try await ConversationsEnvironment.profiles.forgetVoice(VoicePerson.ownerID) }
            }, onDeletePerson: { id in model.perform { try await ConversationsEnvironment.profiles.delete(id) } }
        )
        .sheet(isPresented: $showEnrollment, onDismiss: { enrollment.finish(save: false) }) {
            TimelineView(.periodic(from: .now, by: 1)) { time in
                ConversationEnrollmentView(
                    elapsed: enrollment.startedAt.map { time.date.timeIntervalSince($0) } ?? 0,
                    isRecording: enrollment.startedAt != nil, level: { enrollment.level },
                    onStart: { Task { await enrollment.start() } },
                    onFinish: {
                        enrollment.finish(save: true)
                        showEnrollment = false
                    },
                    onCancel: {
                        enrollment.finish(save: false)
                        showEnrollment = false
                    })
            }
        }
        .alert("Gespräche", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}
