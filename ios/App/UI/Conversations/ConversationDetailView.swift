import PaplyKit
import SwiftUI

/// Alle Aktionen bleiben beim Aufrufer, auch Zwischenablage und Wiedergabe.
struct ConversationDetailActions {
    var rename: (String) -> Void
    var chooseTopic: () -> Void
    var speaker: (String) -> Void
    var suggestion: (String, Bool) -> Void
    var toggleTask: (String) -> Void
    var play: (String) -> Void
    var reassign: (String) -> Void
    var copyUtterance: (String) -> Void
    var playFrom: (String) -> Void
    var share: () -> Void
    var copyTranscript: () -> Void
    var retry: () -> Void
    var delete: () -> Void
}

struct ConversationDetailView: View {
    let item: ConversationDisplay
    let utterances: [ConversationUtterance]
    /// nil = keine Wiedergabe. Erneutes Tippen kann der Aufrufer als Pause behandeln.
    let playingUtteranceID: String?
    var audioAvailable = true
    var pendingTaskIDs: Set<String> = []
    let actions: ConversationDetailActions
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false

    private var conversation: Conversation { item.conversation }
    private var speakers: [String: ConversationSpeaker] {
        Dictionary(conversation.speakers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var suggestion: ConversationSpeaker? {
        conversation.speakers.filter { $0.suggestion != nil && $0.name == nil && !$0.isOwner }
            .max { $0.speechSeconds < $1.speechSeconds }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                ConversationStatusBand(conversation: conversation, onRetry: actions.retry)
                suggestionBand
                summarySection
                tasksAndCommitments
                Text("Wortlaut").font(.headline)
                if !audioAvailable { Text("Der Ton ist nicht mehr verfügbar. Der Wortlaut bleibt.").font(.footnote).foregroundStyle(Color.paplySecondaryText) }
                ForEach(utterances) { utterance in
                    ConversationUtteranceRow(utterance: utterance, speaker: speakers[utterance.speakerID],
                        isPlaying: playingUtteranceID == utterance.id, audioAvailable: audioAvailable,
                        onPlay: { actions.play(utterance.id) }, onReassign: { actions.reassign(utterance.id) },
                        onCopy: { actions.copyUtterance(utterance.id) }, onPlayFrom: { actions.playFrom(utterance.id) })
                }
            }.padding(20).padding(.bottom, 30)
        }
        .background(PaplyBackground()).foregroundStyle(Color.paplyText).tint(ConversationTint.blue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Teilen", systemImage: "square.and.arrow.up", action: actions.share)
                    Button("Wortlaut kopieren", systemImage: "doc.on.doc", action: actions.copyTranscript)
                    Button("Erneut auswerten", systemImage: "arrow.clockwise", action: actions.retry)
                    Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Gesprächsaktionen")
            }
        }
        .alert("Gespräch umbenennen", isPresented: $editingTitle) {
            TextField("Titel", text: $titleDraft)
            Button("Speichern") { actions.rename(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Gespräch löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: actions.delete)
        } message: { Text("Es liegt danach 30 Tage unter „Zuletzt gelöscht“.") }
    }
    @ViewBuilder private var suggestionBand: some View {
        if let speaker = suggestion, let name = speaker.suggestion?.name {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ist \(ConversationTint.name(speaker)) \(name)?")
                HStack {
                    Button("Ja") { actions.suggestion(speaker.id, true) }.frame(minWidth: 60, minHeight: 44)
                    Button("Nein") { actions.suggestion(speaker.id, false) }.frame(minWidth: 60, minHeight: 44)
                }.buttonStyle(.bordered)
            }.font(.subheadline).padding(14).frame(maxWidth: .infinity, alignment: .leading).paplyCard()
        }
    }
    @ViewBuilder private var summarySection: some View {
        if let summary = conversation.summary {
            Text("Zusammenfassung").font(.headline)
            Text(summary.overview).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(ConversationTint.turquoise)
                    Text(point).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if conversation.summary == nil && conversation.state != .done {
            Text("Zusammenfassung").font(.headline)
            Text(conversation.presentationStatus ?? "Entsteht nach der Aufnahme")
                .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
                .shimmer(conversation.state == .analyzing)
        }
    }
    @ViewBuilder private var tasksAndCommitments: some View {
        if !item.tasks.isEmpty {
            Text("Aufgaben").font(.headline)
            ForEach(item.tasks) { task in
                ConversationTaskRow(task: task, recordedAt: conversation.createdAt,
                                    pendingDone: pendingTaskIDs.contains(task.id)) { actions.toggleTask(task.id) }
            }
        }
        if let commitments = conversation.summary?.commitments, !commitments.isEmpty {
            Text("Zusagen der anderen").font(.headline)
            ForEach(commitments) { commitment in
                VStack(alignment: .leading, spacing: 5) {
                    if let speaker = speakers[commitment.speakerID] { ConversationSpeakerLabel(speaker: speaker).font(.subheadline.weight(.medium)) }
                    Text(commitment.text)
                    if let due = commitment.dueHint { Text(due).font(.caption).foregroundStyle(Color.paplySecondaryText) }
                }
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                titleDraft = conversation.title ?? "Neues Gespräch"
                editingTitle = true
            } label: {
                Text(conversation.title ?? "Neues Gespräch").font(.paplyTitle(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityHint("Titel umbenennen")
            Text("\(conversation.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ConversationTint.duration(conversation.durationMs))")
                .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
            Button(action: actions.chooseTopic) {
                Label(item.topic ?? "Thema wählen", systemImage: "tag")
                    .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 44).paplyGlass()
            }.buttonStyle(.plain)
            ConversationChipLayout {
                ForEach(conversation.speakers) { speaker in
                    Button { actions.speaker(speaker.id) } label: {
                        ConversationSpeakerLabel(speaker: speaker, showSuggestion: true)
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 44).paplyGlass()
                    }.buttonStyle(.plain).accessibilityHint("Wer ist das? Stimme zuordnen")
                }
            }
        }
    }
}

struct ConversationTaskRow: View {
    let task: ThoughtTask
    let recordedAt: Date
    var pendingDone = false
    let onToggle: () -> Void
    private var done: Bool { task.done || pendingDone }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                TaskCheckCircle(done: done).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(PressScaleStyle(scale: 0.86))
                .accessibilityLabel(done ? "Wieder öffnen: \(task.text)" : "Abhaken: \(task.text)")
            VStack(alignment: .leading, spacing: 6) {
                Text(task.text).strikethrough(done).foregroundStyle(done ? Color.paplySecondaryText : .paplyText)
                if let due = TaskDueLabel.make(task: task, recordedAt: recordedAt) {
                    Text(TaskDueText.text(due)).font(.footnote).foregroundStyle(Color.paplySecondaryText)
                }
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .sensoryFeedback(trigger: done) { _, new in new ? .impact(weight: .light) : .selection }
    }
}

struct ConversationUtteranceRow: View {
    let utterance: ConversationUtterance
    let speaker: ConversationSpeaker?
    let isPlaying: Bool
    let audioAvailable: Bool
    let onPlay: () -> Void
    let onReassign: () -> Void
    let onCopy: () -> Void
    let onPlayFrom: () -> Void
    var body: some View {
        Button { if audioAvailable { onPlay() } } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(speaker.map(ConversationTint.name) ?? "Unbekannter Sprecher")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(speaker.map(ConversationTint.color) ?? ConversationTint.blue)
                    Text(ConversationTint.clock(utterance.start)).font(.caption).foregroundStyle(Color.paplySecondaryText)
                    if isPlaying { Label("Läuft", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(ConversationTint.blue) }
                }
                Text(utterance.text).foregroundStyle(Color.paplyText).multilineTextAlignment(.leading)
                if utterance.uncertain {
                    Label("Sprecher nicht sicher", systemImage: "questionmark.circle").font(.caption).foregroundStyle(Color.paplySecondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
            .background(isPlaying ? ConversationTint.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(audioAvailable ? (isPlaying ? "Wiedergabe anhalten" : "Diese Stelle anhören") : "Ton nicht mehr verfügbar")
        .contextMenu {
            Button("Anderer Sprecher …", systemImage: "person.crop.circle", action: onReassign)
            Button("Text kopieren", systemImage: "doc.on.doc", action: onCopy)
            Button("Ab hier anhören", systemImage: "play", action: onPlayFrom).disabled(!audioAvailable)
        }
        .accessibilityAction(named: "Anderer Sprecher …", onReassign)
        .accessibilityAction(named: "Text kopieren", onCopy)
    }
}

#Preview("Detail") { NavigationStack { ConversationDetailPreview(item: ConversationsPreviewData.phone) }.preferredColorScheme(.dark) }
#Preview("Aufgabe") { ConversationTaskRow(task: ConversationsPreviewData.phone.tasks[0], recordedAt: .now, onToggle: {}).padding().background(PaplyBackground()).preferredColorScheme(.dark) }
#Preview("Beitrag") {
    ConversationUtteranceRow(utterance: ConversationsPreviewData.utterances[0], speaker: ConversationsPreviewData.phone.conversation.speakers[0], isPlaying: true, audioAvailable: true, onPlay: {}, onReassign: {}, onCopy: {}, onPlayFrom: {})
        .background(PaplyBackground()).preferredColorScheme(.dark)
}
