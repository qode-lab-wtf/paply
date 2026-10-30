import PaplyKit
import SwiftUI

struct ConversationSettingsHost: View {
    @State private var model = ConversationsModel.shared
    var body: some View {
        // Keine Modifier wie .sheet/.alert an der Section: In einer Form verteilt SwiftUI sie auf jede Zeile.
        ConversationSettingsSection(
            learnedThoughtCount: model.learnedThoughtCount, people: model.people,
            onForgetOwner: { model.perform { try await ConversationsEnvironment.profiles.forgetVoice(VoicePerson.ownerID) } },
            onDeletePerson: { id in model.perform { try await ConversationsEnvironment.profiles.delete(id) } },
            error: Binding(get: { model.error }, set: { model.error = $0 })
        )
    }
}

/// Als Blatt (Hinweis-Pille im Reiter „Gespräche“): eigener Navigationsstapel um die Einsprech-Seite.
struct ConversationEnrollmentSheet: View {
    var body: some View {
        NavigationStack { ConversationEnrollmentPage() }
    }
}

/// Einsprechen (20 s). Als Seite in den Einstellungen bzw. im Blatt der Hinweis-Pille; endet nur durch Nutzeraktion.
struct ConversationEnrollmentPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enrollment = ConversationEnrollment()
    @State private var saved = false
    var body: some View {
        Group {
            if saved {
                VStack(spacing: 20) {
                    Text("Stimmaufnahme gesichert").font(.headline)
                    Text("Paply lernt deine Stimme, sobald die Sprechererkennung bereit ist.")
                    if let error = ConversationsModel.shared.error { Text(error) }
                    Button("Schließen") { dismiss() }
                }.padding()
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    ConversationEnrollmentView(
                        elapsed: enrollment.startedAt.map { time.date.timeIntervalSince($0) } ?? 0,
                        isRecording: enrollment.startedAt != nil, level: { enrollment.level },
                        onStart: { Task { await enrollment.start() } },
                        onFinish: { enrollment.finish(save: true) },
                        onCancel: { enrollment.finish(save: false); dismiss() })
                }
                .onChange(of: enrollment.startedAt) { old, new in
                    if old != nil && new == nil && enrollment.error == nil { saved = true }
                }
            }
        }
        .interactiveDismissDisabled(enrollment.starting || enrollment.startedAt != nil)
        .onDisappear { enrollment.finish(save: false) }
        .alert("Einsprechen", isPresented: Binding(get: { enrollment.error != nil }, set: { if !$0 { enrollment.error = nil } })) {
            Button("OK") { enrollment.error = nil }
        } message: { Text(enrollment.error ?? "") }
    }
}
