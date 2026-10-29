import PaplyKit
import SwiftUI

/// In ein Form/List einhängbar. `learnedThoughtCount == nil`: Stimme noch nicht gelernt.
struct ConversationSettingsSection: View {
    let learnedThoughtCount: Int?
    let people: [VoicePerson]
    let onEnroll: () -> Void
    let onForgetOwner: () -> Void
    let onDeletePerson: (String) -> Void
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meine Stimme").font(.headline)
                if let count = learnedThoughtCount {
                    Label("Gelernt aus \(count) Gedanken", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.paplyGreenBright)
                } else {
                    Text("Noch nicht gelernt – nimm ein paar Gedanken auf oder tippe im ersten Gespräch auf „Das bin ich“.")
                        .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
                }
            }
            Button("Jetzt einsprechen (20 s)", action: onEnroll)
            if learnedThoughtCount != nil { Button("Stimme vergessen", role: .destructive, action: onForgetOwner) }
            NavigationLink("Bekannte Stimmen") {
                ConversationKnownVoicesView(people: people, onDelete: onDeletePerson)
            }
        } header: { Text("Gespräche") } footer: {
            Text("Alle Beteiligten müssen einer Aufnahme zustimmen (§ 201 StGB). Sprechererkennung und Stimmprofile bleiben auf deinem iPhone. Groq erhält den Ton zum Verschriftlichen und den Wortlaut für die Zusammenfassung.")
        }.listRowBackground(Color.paplyRow)
    }
}

struct ConversationKnownVoicesView: View {
    let people: [VoicePerson]
    let onDelete: (String) -> Void
    var body: some View {
        List {
            if people.filter({ !$0.isOwner }).isEmpty { Text("Noch keine bekannten Stimmen").foregroundStyle(Color.paplySecondaryText) }
            ForEach(people.filter { !$0.isOwner }) { person in
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.name).fixedSize(horizontal: false, vertical: true)
                    Text("Seit \(person.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(Color.paplySecondaryText)
                }.frame(minHeight: 44).listRowBackground(Color.paplyRow)
                    .swipeActions { Button("Vergessen", role: .destructive) { onDelete(person.id) } }
                    .accessibilityAction(named: "Stimme vergessen") { onDelete(person.id) }
            }
        }.paplyList().navigationTitle("Bekannte Stimmen")
    }
}

struct ConversationEnrollmentView: View {
    let elapsed: Double
    let isRecording: Bool
    let level: () -> Float
    let onStart: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                EchoOrb(size: 160, mode: isRecording ? .listening : .starting,
                        primary: ConversationTint.blue, secondary: ConversationTint.turquoise,
                        auraColors: [ConversationTint.blue, ConversationTint.turquoise], level: level).padding(.top, 48)
                Text("\(max(0, 20 - Int(elapsed))) s").font(.system(.largeTitle, design: .rounded).monospacedDigit())
                Text("Erzähl kurz von deinem Tag. So erkennt Paply deine Stimme im nächsten Gespräch.")
                    .multilineTextAlignment(.center).foregroundStyle(Color.paplySecondaryText)
                Button(isRecording ? "Fertig" : "Einsprechen starten", action: isRecording ? onFinish : onStart)
                    .buttonStyle(.borderedProminent).tint(ConversationTint.blue).frame(minHeight: 44)
            }.padding(24).frame(maxWidth: .infinity)
        }.background(PaplyBackground()).foregroundStyle(Color.paplyText).navigationTitle("Meine Stimme")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) } }
    }
}

#Preview("Einstellungen") {
    NavigationStack { Form { ConversationSettingsSection(learnedThoughtCount: 4, people: ConversationsPreviewData.people, onEnroll: {}, onForgetOwner: {}, onDeletePerson: { _ in }) }.paplyList() }.preferredColorScheme(.dark)
}
#Preview("Stimmen") { NavigationStack { ConversationKnownVoicesView(people: ConversationsPreviewData.people, onDelete: { _ in }) }.preferredColorScheme(.dark) }
#Preview("Einsprechen") { NavigationStack { ConversationEnrollmentView(elapsed: 8, isRecording: true, level: { 0.3 }, onStart: {}, onFinish: {}, onCancel: {}) }.preferredColorScheme(.dark) }
