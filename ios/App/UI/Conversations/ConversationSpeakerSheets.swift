import PaplyKit
import SwiftUI

/// Auswahl ist explizit: bestehende Person, eigener Name, Zusammenlegen oder nur lokal im Gespräch.
enum ConversationSpeakerChoice {
    case suggestion(SpeakerSuggestion)
    case person(String)
    case newName(String)
    case merge(String)
    case doNotRemember
}

struct ConversationSpeakerSheet: View {
    let speaker: ConversationSpeaker
    let speakers: [ConversationSpeaker]
    let people: [VoicePerson]
    let onChoose: (ConversationSpeakerChoice) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                if let suggestion = speaker.suggestion {
                    Section(speaker.suggestion?.source == .transcript ? "Aus dem Gespräch vorgeschlagen" : "Bekannte Stimme vorgeschlagen") {
                        Button { onChoose(.suggestion(suggestion)) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(suggestion.name) ?").font(.headline)
                                if let evidence = suggestion.evidence {
                                    Text("„\(evidence)“").font(.subheadline).foregroundStyle(Color.paplySecondaryText)
                                } else { Text("Ähnelt einer bekannten Stimme").font(.caption) }
                            }.padding(.vertical, 6)
                        }
                    }.listRowBackground(Color.paplyRow)
                }
                Section("Bekannte Stimmen") {
                    ForEach(people.filter { !$0.isOwner }) { person in
                        Button(person.name) { onChoose(.person(person.id)) }.frame(minHeight: 44)
                    }
                    Button("Das bin ich") { onChoose(.person(VoicePerson.ownerID)) }.frame(minHeight: 44)
                }.listRowBackground(Color.paplyRow)
                Section("Neuer Name") {
                    TextField("Wie heißt die Person?", text: $name).textContentType(.name)
                    Button("Namen übernehmen") { onChoose(.newName(name.trimmingCharacters(in: .whitespacesAndNewlines))) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.listRowBackground(Color.paplyRow)
                Section {
                    NavigationLink("Mit anderem Sprecher zusammenlegen …") {
                        ConversationUtteranceSpeakerSheet(speakers: speakers.filter { $0.id != speaker.id }, selectedID: nil,
                            title: "Zusammenlegen", onChoose: { onChoose(.merge($0)) }, onCancel: onCancel)
                    }.disabled(speakers.count < 2)
                    Button("Stimme nicht merken") { onChoose(.doNotRemember) }
                } footer: { Text("Bestätigte Stimmen merkt sich Paply nur auf diesem iPhone.") }.listRowBackground(Color.paplyRow)
            }
            .paplyList().navigationTitle("Wer ist das?").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).tint(ConversationTint.blue)
    }
}

struct ConversationUtteranceSpeakerSheet: View {
    let speakers: [ConversationSpeaker]
    let selectedID: String?
    var title = "Anderer Sprecher …"
    let onChoose: (String) -> Void
    let onCancel: () -> Void
    var body: some View {
        List(speakers) { speaker in
            Button { onChoose(speaker.id) } label: {
                HStack {
                    ConversationSpeakerLabel(speaker: speaker)
                    Spacer()
                    if selectedID == speaker.id { Image(systemName: "checkmark").accessibilityLabel("Ausgewählt") }
                }.frame(minHeight: 44)
            }.listRowBackground(Color.paplyRow)
        }
        .paplyList().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) } }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}

#Preview("Wer ist das?") {
    ConversationSpeakerSheet(speaker: ConversationsPreviewData.phone.conversation.speakers[1], speakers: ConversationsPreviewData.phone.conversation.speakers, people: ConversationsPreviewData.people, onChoose: { _ in }, onCancel: {}).preferredColorScheme(.dark)
}
#Preview("Anderer Sprecher") {
    NavigationStack { ConversationUtteranceSpeakerSheet(speakers: ConversationsPreviewData.phone.conversation.speakers, selectedID: "S1", onChoose: { _ in }, onCancel: {}) }.preferredColorScheme(.dark)
}
