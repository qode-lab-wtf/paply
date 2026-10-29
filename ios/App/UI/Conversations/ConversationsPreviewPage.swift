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
    var showPreviewHint = true
    var onSettings: (() -> Void)? = nil
    @State private var recording = false
    var body: some View {
        ConversationsHome(items: empty ? [] : ConversationsPreviewData.all, showPrivacyHint: true,
            onRecord: { recording = true }, onOpen: { selected = $0 }, onVoices: { showVoices = true },
            onDeleted: { showDeleted = true }, onSettings: { if let onSettings { onSettings() } else { showVoices = true } })
            .safeAreaInset(edge: .top) {
                if showPreviewHint { Text("Vorschau · Beispieldaten").font(.caption).foregroundStyle(Color.paplySecondaryText).padding(6) }
            }
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
    @State private var selectedSpeaker: ConversationSpeaker?
    @State private var selectedUtterance: ConversationUtterance?
    @State private var showTopic = false
    @State private var showShare = false
    @State private var note: String?
    @Environment(\.dismiss) private var dismiss
    private var utterances: [ConversationUtterance] {
        item.id == "preview-long" ? ConversationsPreviewData.longUtterances :
            item.id == "preview-meeting" ? [
                .init(id: "g1", speakerID: "S1", start: 12, end: 20, text: "Ich besorge Saatgut und Handschuhe für Samstag."),
                .init(id: "g2", speakerID: "S2", start: 30, end: 38, text: "Die Jungpflanzen bringe ich mit."),
                .init(id: "g3", speakerID: "S3", start: 40, end: 48, text: "Ich organisiere die Schubkarre."),
                .init(id: "g4", speakerID: "S4", start: 50, end: 58, text: "Dann prüfe ich vorher den Wasseranschluss.")
            ] : ConversationsPreviewData.utterances
    }
    var body: some View {
        ConversationDetailView(item: item, utterances: utterances, actions: .init(
            rename: { item.conversation.title = $0 }, chooseTopic: { showTopic = true },
            speaker: { id in selectedSpeaker = item.conversation.speakers.first { $0.id == id } },
            identifyOwner: { id in
                for i in item.conversation.speakers.indices {
                    let isOwner = item.conversation.speakers[i].id == id
                    item.conversation.speakers[i].personID = isOwner ? VoicePerson.ownerID : nil
                    item.conversation.speakers[i].nameSource = isOwner ? .owner : .none
                }
            },
            suggestion: { id, yes in
                guard let i = item.conversation.speakers.firstIndex(where: { $0.id == id }) else { return }
                if yes { item.conversation.speakers[i].name = item.conversation.speakers[i].suggestion?.name }
                item.conversation.speakers[i].suggestion = nil
            }, toggleTask: { id in if let i = item.tasks.firstIndex(where: { $0.id == id }) { item.tasks[i].done.toggle() } },
            reassign: { id in selectedUtterance = utterances.first { $0.id == id } },
            copyUtterance: { _ in note = "Vorschau: Text kopieren" },
            share: { showShare = true }, copyTranscript: { note = "Vorschau: Wortlaut kopieren" },
            retry: { note = "Vorschau: Auswertung erneut starten" }, delete: { dismiss() }))
        .sheet(item: $selectedSpeaker) { speaker in
            ConversationSpeakerSheet(speaker: speaker, speakers: item.conversation.speakers, people: ConversationsPreviewData.people,
                onChoose: { choice, _ in
                    if let i = item.conversation.speakers.firstIndex(where: { $0.id == speaker.id }) {
                        switch choice {
                        case .suggestion(let suggestion): item.conversation.speakers[i].name = suggestion.name
                        case .person(let id):
                            item.conversation.speakers[i].personID = id
                            item.conversation.speakers[i].nameSource = .user
                            item.conversation.speakers[i].name = ConversationsPreviewData.people.first { $0.id == id }?.name
                        case .newName(let name): item.conversation.speakers[i].name = name
                        case .merge: note = "Vorschau: Personen zusammenlegen"
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
    @State var paused = false
    @State private var minimized = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if minimized {
                VStack {
                    Text("Aufnahme-Vorschau").font(.title)
                    Text("Keine echte Aufnahme").foregroundStyle(Color.paplySecondaryText)
                    Spacer()
                    ConversationRecordingBar(elapsed: 1421, paused: paused, level: { 0.25 }, onOpen: { minimized = false }, onPause: { paused.toggle() }, onFinish: { dismiss() })
                }.padding(.top, 40).background(PaplyBackground())
            } else {
                ConversationRecordingView(elapsed: 1421, paused: paused, pausedSince: paused ? .now.addingTimeInterval(-120) : nil, showGuidance: true, level: { 0.25 },
                    onPause: { paused.toggle() }, onFinish: { dismiss() }, onDiscard: { dismiss() }, onMinimize: { minimized = true })
            }
        }
    }
}

struct ConversationSettingsPreview: View {
    @State private var people = ConversationsPreviewData.people
    @State var learned: Int? = 4
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
    @State private var startedAt: Date?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { time in
            let elapsed = startedAt.map { time.date.timeIntervalSince($0) } ?? 0
            ConversationEnrollmentView(elapsed: elapsed, isRecording: startedAt != nil, level: { 0.25 },
                onStart: { startedAt = .now }, onFinish: { dismiss() }, onCancel: { dismiss() })
                .onChange(of: elapsed) { _, value in if value >= 20 { dismiss() } }
        }
    }
}

#Preview("Vorschauseite") { NavigationStack { ConversationsPreviewPage() }.preferredColorScheme(.dark) }
#Preview("Langer Wortlaut") { NavigationStack { ConversationDetailPreview(item: ConversationsPreviewData.long) }.preferredColorScheme(.dark) }

#if DEBUG
/// Nur für Bildschirmfotos; keine Aufnahme, Netzwerkzugriffe oder Speicheränderungen.
enum ConversationDevPreviewRoute: String, Identifiable {
    case home, recording, bar, settings, enrollment, licenses
    case homeEmpty = "home-empty"
    case recordingPaused = "recording-paused"
    case detailCall = "detail-call"
    case detailMeeting = "detail-meeting"
    case detailProcessing = "detail-processing"
    case detailWaiting = "detail-waiting"
    case speakerSheet = "speaker-sheet"
    case utteranceSheet = "utterance-sheet"
    case settingsUnlearned = "settings-unlearned"
    case thoughtRow = "thought-row"
    case modelsLoading = "models-loading"
    var id: String { rawValue }
}

struct ConversationDevPreview: View {
    let route: ConversationDevPreviewRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            screen
                .background(PaplyBackground())
                .toolbar {
                    if route != .speakerSheet && route != .utteranceSheet && route != .enrollment {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Schließen") { dismiss() }
                        }
                    }
                }
        }
        .id(route)
        .preferredColorScheme(.dark)
        .tint(ConversationTint.blue)
    }

    @ViewBuilder private var screen: some View {
        switch route {
        case .home: ConversationsPreviewHost(showPreviewHint: false)
        case .homeEmpty: ConversationsPreviewHost(empty: true, showPreviewHint: false)
        case .recording: ConversationRecordingPreview()
        case .recordingPaused: ConversationRecordingPreview(paused: true)
        case .bar:
            ConversationsPreviewHost(showPreviewHint: false)
                .safeAreaInset(edge: .bottom) {
                    ConversationRecordingBar(elapsed: 1421, paused: false, level: { 0.25 }, onOpen: {}, onFinish: {})
                }
        case .detailCall: ConversationDetailPreview(item: ConversationsPreviewData.callUnknownOwner)
        case .detailMeeting: ConversationDetailPreview(item: ConversationsPreviewData.meetingWithTasks)
        case .detailProcessing: ConversationDetailPreview(item: ConversationsPreviewData.partlyProcessed)
        case .detailWaiting: ConversationDetailPreview(item: ConversationsPreviewData.waiting)
        case .speakerSheet:
            ConversationSpeakerSheet(speaker: ConversationsPreviewData.speakers[1],
                speakers: ConversationsPreviewData.speakers, people: ConversationsPreviewData.people,
                onChoose: { _, _ in }, onCancel: { dismiss() }, cancelTitle: "Schließen")
        case .utteranceSheet:
            ConversationUtteranceSpeakerSheet(speakers: ConversationsPreviewData.speakers,
                selectedID: "S1", onChoose: { _ in }, onCancel: { dismiss() }, cancelTitle: "Schließen")
        case .settings, .settingsUnlearned:
            Form {
                ConversationSettingsSection(learnedThoughtCount: route == .settings ? 4 : nil,
                    people: ConversationsPreviewData.people, onEnroll: {}, onForgetOwner: {}, onDeletePerson: { _ in })

            }.paplyList().navigationTitle("Einstellungen")
        case .enrollment:
            ConversationEnrollmentView(elapsed: 8, isRecording: true, level: { 0.25 },
                onStart: {}, onFinish: { dismiss() }, onCancel: { dismiss() }, cancelTitle: "Schließen")
        case .thoughtRow:
            List {
                Section("Heute") {
                    thought("Idee für den Gartentag", text: "Am Samstag gemeinsam die Hochbeete vorbereiten.", time: "14:32")
                    ConversationThoughtRow(item: ConversationsPreviewData.phone, time: "14:05")
                    thought("Einkauf für morgen", text: "Hafermilch und frisches Brot mitbringen.", time: "09:18")
                }.listRowBackground(Color.paplyRow)
            }.paplyList().navigationTitle("Gedanken")
        case .modelsLoading:
            ConversationsPreviewHost(showPreviewHint: false)
                .safeAreaInset(edge: .top) {
                    Text("Sprechererkennung wird geladen … 42 %").font(.footnote)
                        .foregroundStyle(Color.paplySecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 8)
                }
        case .licenses: ConversationLicenses()
        }
    }

    private func thought(_ title: String, text: String, time: String) -> some View {
        ThoughtRow(thought: Thought(trigger: .app, state: .done, title: title, text: text),
            topic: nil, showTopic: false, time: time)
    }
}
#endif
