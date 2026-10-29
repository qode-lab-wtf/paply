import PaplyKit
import SwiftUI

/// PLATZHALTER: In RootView durch die echte ConversationsModel-Verdrahtung ersetzen.
/// Sämtliche Änderungen sind nur im Speicher dieser Vorschau.
struct ConversationsPlaceholderTab: View {
    var onSettings: () -> Void
    var body: some View {
        NavigationStack { ConversationsPreviewHost(onSettings: onSettings) }
    }
}

struct ConversationsPreviewPage: View {
    var body: some View {
        List {
            Section("Beispieldaten · keine echte Aufnahme") {
                NavigationLink("Übersicht") { ConversationsPreviewHost() }
                NavigationLink("Leere Übersicht") { ConversationsPreviewHost(empty: true) }
                NavigationLink("Aufnahme und schmale Leiste") { ConversationRecordingPreview() }
                NavigationLink("Aufnahme pausiert – Anruf") { ConversationRecordingPreview(paused: true) }
                exampleLinks
                NavigationLink("Stimmen und Datenschutz") { ConversationSettingsPreview() }
                NavigationLink("Einsprechen") { ConversationEnrollmentPreview() }
                NavigationLink("Zeile in Gedanken") {
                    List { ConversationThoughtRow(item: ConversationsPreviewData.phone, time: "14:05")
                        .listRowBackground(Color.paplyRow) }.paplyList()
                }
            }.listRowBackground(Color.paplyRow)
        }.paplyList().navigationTitle("Gespräche-Vorschau").tint(ConversationTint.blue)
    }
    private var exampleLinks: some View {
        ForEach(ConversationsPreviewData.all) { item in
            NavigationLink {
                ConversationDetailPreview(item: item)
            } label: {
                Text(exampleTitle(item))
            }
        }
    }
    private func exampleTitle(_ item: ConversationDisplay) -> String {
        if item.id == "preview-long" { return "1.200 Beiträge · Scroll-Test" }
        let title = item.conversation.title ?? "Neues Gespräch"
        let status = item.conversation.presentationStatus ?? "Fertig"
        return title + " · " + status
    }

}

struct ConversationsPreviewHost: View {
    var empty = false
    var onSettings: (() -> Void)? = nil
    @State private var recording = false
    var body: some View {
        ConversationsHome(items: empty ? [] : ConversationsPreviewData.all, showPrivacyHint: true,
            onRecord: { recording = true }, onOpen: { selected = $0 }, onVoices: { showVoices = true },
            onDeleted: { showDeleted = true }, onSettings: { if let onSettings { onSettings() } else { showVoices = true } })
            .safeAreaInset(edge: .top) { Text("Vorschau · Beispieldaten").font(.caption).foregroundStyle(Color.paplySecondaryText).padding(6) }
            .navigationDestination(item: $selected) { id in
                if let item = ConversationsPreviewData.all.first(where: { $0.id == id }) { ConversationDetailPreview(item: item) }
            }
            .navigationDestination(isPresented: $showVoices) { ConversationSettingsPreview() }
            .alert("Zuletzt gelöscht", isPresented: $showDeleted) {} message: { Text("In der Vorschau ist der Papierkorb leer.") }
            .fullScreenCover(isPresented: $recording) { ConversationRecordingPreview() }
    }
    @State private var selected: String?
    @State private var showVoices = false
    @State private var showDeleted = false
}

struct ConversationDetailPreview: View {
    @State var item: ConversationDisplay
    @State private var playing: String?
    @State private var selectedSpeaker: ConversationSpeaker?
    @State private var selectedUtterance: ConversationUtterance?
    @State private var showTopic = false
    @State private var showShare = false
    @State private var note: String?
    @Environment(\.dismiss) private var dismiss
    private var utterances: [ConversationUtterance] {
        item.id == "preview-long" ? ConversationsPreviewData.longUtterances : ConversationsPreviewData.utterances
    }
    var body: some View {
        ConversationDetailView(item: item, utterances: utterances, playingUtteranceID: playing, actions: .init(
            rename: { item.conversation.title = $0 }, chooseTopic: { showTopic = true },
            speaker: { id in selectedSpeaker = item.conversation.speakers.first { $0.id == id } },
            suggestion: { id, yes in
                guard let i = item.conversation.speakers.firstIndex(where: { $0.id == id }) else { return }
                if yes { item.conversation.speakers[i].name = item.conversation.speakers[i].suggestion?.name }
                item.conversation.speakers[i].suggestion = nil
            }, toggleTask: { id in if let i = item.tasks.firstIndex(where: { $0.id == id }) { item.tasks[i].done.toggle() } },
            play: { playing = playing == $0 ? nil : $0 },
            reassign: { id in selectedUtterance = utterances.first { $0.id == id } },
            copyUtterance: { _ in note = "Vorschau: Text kopieren" }, playFrom: { playing = $0 },
            share: { showShare = true }, copyTranscript: { note = "Vorschau: Wortlaut kopieren" },
            retry: { note = "Vorschau: Auswertung erneut starten" }, delete: { dismiss() }))
        .sheet(item: $selectedSpeaker) { speaker in
            ConversationSpeakerSheet(speaker: speaker, speakers: item.conversation.speakers, people: ConversationsPreviewData.people,
                onChoose: { choice in
                    if let i = item.conversation.speakers.firstIndex(where: { $0.id == speaker.id }) {
                        switch choice {
                        case .suggestion(let suggestion): item.conversation.speakers[i].name = suggestion.name
                        case .person(let id):
                            item.conversation.speakers[i].personID = id
                            item.conversation.speakers[i].name = ConversationsPreviewData.people.first { $0.id == id }?.name
                        case .newName(let name): item.conversation.speakers[i].name = name
                        case .merge: note = "Vorschau: Sprecher zusammenlegen"
                        case .doNotRemember: note = "Vorschau: Stimme wird nicht gemerkt"
                        }
                        item.conversation.speakers[i].suggestion = nil
                    }
                    selectedSpeaker = nil
                }, onCancel: { selectedSpeaker = nil })
        }
        .sheet(item: $selectedUtterance) { utterance in
            NavigationStack {
                ConversationUtteranceSpeakerSheet(speakers: item.conversation.speakers, selectedID: utterance.speakerID,
                    onChoose: { _ in selectedUtterance = nil; note = "Vorschau: Beitrag zugeordnet" }, onCancel: { selectedUtterance = nil })
            }
        }
        .confirmationDialog("Thema wählen", isPresented: $showTopic) {
            Button("Sonnenwerk") { item.topic = "Sonnenwerk" }
            Button("Garten") { item.topic = "Garten" }
            Button("Ohne Thema") { item.topic = nil }
        }
        .sheet(isPresented: $showShare) { ScrollView { Text(item.conversation.summary?.overview ?? "Noch keine Zusammenfassung").padding() }.presentationDetents([.medium]) }
        .alert("Beispieldaten", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK") { note = nil }
        } message: { Text(note ?? "") }
    }
}

struct ConversationRecordingPreview: View {
    var paused = false
    @State private var minimized = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if minimized {
                VStack {
                    Text("Aufnahme-Vorschau").font(.title)
                    Text("Keine echte Aufnahme").foregroundStyle(Color.paplySecondaryText)
                    Spacer()
                    ConversationRecordingBar(elapsed: 1421, paused: paused, level: { 0.25 }, onOpen: { minimized = false }, onFinish: { dismiss() })
                }.padding(.top, 40).background(PaplyBackground())
            } else {
                ConversationRecordingView(elapsed: 1421, paused: paused, showGuidance: true, level: { 0.25 },
                    onFinish: { dismiss() }, onDiscard: { dismiss() }, onMinimize: { minimized = true })
            }
        }
    }
}

struct ConversationSettingsPreview: View {
    @State private var people = ConversationsPreviewData.people
    @State private var learned: Int? = 4
    @State private var enroll = false
    var body: some View {
        Form {
            ConversationSettingsSection(learnedThoughtCount: learned, people: people, onEnroll: { enroll = true },
                onForgetOwner: { learned = nil }, onDeletePerson: { id in people.removeAll { $0.id == id } })
        }.paplyList().navigationTitle("Gespräche")
            .navigationDestination(isPresented: $enroll) { ConversationEnrollmentPreview() }
    }
}

struct ConversationEnrollmentPreview: View {
    @State private var recording = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ConversationEnrollmentView(elapsed: recording ? 8 : 0, isRecording: recording, level: { 0.25 },
            onStart: { recording = true }, onFinish: { dismiss() }, onCancel: { dismiss() })
    }
}

#Preview("Vorschauseite") { NavigationStack { ConversationsPreviewPage() }.preferredColorScheme(.dark) }
#Preview("Langer Wortlaut") { NavigationStack { ConversationDetailPreview(item: ConversationsPreviewData.long) }.preferredColorScheme(.dark) }
