import PaplyKit
import SwiftUI

/// Alle Aktionen bleiben beim Aufrufer, auch Zwischenablage.
struct ConversationDetailActions {
    var rename: (String) -> Void
    var chooseTopic: () -> Void
    var speaker: (String) -> Void
    var identifyOwner: (String) -> Void
    var suggestion: (String, Bool) -> Void
    var toggleTask: (String) -> Void
    var reassign: (String) -> Void
    var copyUtterance: (String) -> Void
    var share: () -> Void
    var copyTranscript: () -> Void
    var retry: () -> Void
    var delete: () -> Void
}

struct ConversationDetailView: View {
    let item: ConversationDisplay
    let utterances: [ConversationUtterance]
    var pendingTaskIDs: Set<String> = []
    let actions: ConversationDetailActions
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false

    private var conversation: Conversation { item.conversation }
    private var speakers: [String: ConversationSpeaker] {
        Dictionary(conversation.speakers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var needsOwner: Bool {
        !conversation.speakers.contains(where: \.isOwner) && !conversation.speakers.isEmpty
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
                if needsOwner || suggestion != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        ownerCard
                        suggestionBand
                    }
                }
                summarySection
                VStack(alignment: .leading, spacing: 12) { tasksAndCommitments }
                transcriptSection
            }.padding(20).padding(.bottom, 30)
        }
        .background(PaplyBackground()).foregroundStyle(Color.paplyText).tint(ConversationTint.blue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Teilen", systemImage: "square.and.arrow.up", action: actions.share)
                    Button("Wortlaut kopieren", systemImage: "doc.on.doc", action: actions.copyTranscript)
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
    @ViewBuilder private var ownerCard: some View {
        if needsOwner {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welche Person bist du?").font(.subheadline.weight(.semibold))
                Text("Ich bin …").font(.footnote).foregroundStyle(Color.paplySecondaryText)
                ConversationChipLayout {
                    ForEach(conversation.speakers) { speaker in
                        Button { actions.identifyOwner(speaker.id) } label: {
                            ConversationSpeakerLabel(speaker: speaker)
                                .font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44).paplyGlass()
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Das bin ich: \(ConversationTint.name(speaker))")
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).paplyCard()
        }
    }
    @ViewBuilder private var transcriptSection: some View {
        Text("Wortlaut").font(.headline)
        ForEach(Array(utterances.enumerated()), id: \.element.id) { index, utterance in
            ForEach(Array(conversation.gaps.enumerated()).filter { _, gap in
                let previous = index == 0 ? -1.0 : utterances[index - 1].start
                return gap.at > previous && gap.at <= utterance.start
            }, id: \.offset) { _, gap in
                Text(gap.label).font(.caption).foregroundStyle(Color.paplySecondaryText)
            }
            ConversationUtteranceRow(utterance: utterance, speaker: speakers[utterance.speakerID],
                onReassign: { actions.reassign(utterance.id) },
                onCopy: { actions.copyUtterance(utterance.id) })
        }
        ForEach(Array(conversation.gaps.enumerated()).filter { $0.element.at > (utterances.last?.start ?? -1) }, id: \.offset) { _, gap in
            Text(gap.label).font(.caption).foregroundStyle(Color.paplySecondaryText)
        }
    }
    @ViewBuilder private var suggestionBand: some View {
        if let speaker = suggestion, let name = speaker.suggestion?.name {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ist \(ConversationTint.name(speaker)) \(name)?")
                HStack {
                    Button("Ja") { actions.suggestion(speaker.id, true) }.buttonStyle(.borderedProminent).foregroundStyle(Color.paplyForestDeep).frame(minWidth: 60, minHeight: 44)
                    Button("Nein") { actions.suggestion(speaker.id, false) }.frame(minWidth: 60, minHeight: 44)
                }.buttonStyle(.bordered)
            }.font(.subheadline).padding(14).frame(maxWidth: .infinity, alignment: .leading).paplyCard()
        }
    }
    @ViewBuilder private var summarySection: some View {
        if let summary = conversation.summary {
            Text("Zusammenfassung").font(.headline)
            Text(ConversationText.render(summary.overview, speakers: conversation.speakers)).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(ConversationTint.turquoise)
                    Text(ConversationText.render(point, speakers: conversation.speakers)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }

    }
    @ViewBuilder private var tasksAndCommitments: some View {
        Text("Aufgaben").font(.headline)
        if !item.tasks.isEmpty {
            if conversation.speakers.contains(where: \.isOwner) { Text("Ich").font(.subheadline.weight(.medium)) }
            ForEach(item.tasks.filter { task in !(conversation.summary?.commitments.contains { $0.id == task.id && $0.speakerID == "shared" } ?? false) }) { task in
                ConversationTaskRow(task: task, recordedAt: conversation.createdAt,
                                    pendingDone: pendingTaskIDs.contains(task.id)) { actions.toggleTask(task.id) }
            }
        }
        ForEach(conversation.speakers.filter { !$0.isOwner }) { speaker in
            let tasks = conversation.summary?.commitments.filter { $0.speakerID == speaker.id } ?? []
            if !tasks.isEmpty {
                ConversationSpeakerLabel(speaker: speaker).font(.subheadline.weight(.medium))
                ForEach(tasks) { task in
                    Text(ConversationText.render(task.text, speakers: conversation.speakers))
                        .foregroundStyle(Color.paplySecondaryText)
                }
            }
        }
        let shared = conversation.summary?.commitments.filter { $0.speakerID == "shared" } ?? []
        if !shared.isEmpty {
            Text("Gemeinsam / unklar").font(.subheadline.weight(.medium))
            ForEach(shared) { task in
                if let linked = item.tasks.first(where: { $0.id == task.id }) {
                    ConversationTaskRow(task: linked, recordedAt: conversation.createdAt,
                        pendingDone: pendingTaskIDs.contains(linked.id)) { actions.toggleTask(linked.id) }
                } else {
                    Text(ConversationText.render(task.text, speakers: conversation.speakers))
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
                Text(conversation.title ?? "Neues Gespräch").font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
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
                TaskCheckCircle(done: done).padding(11).contentShape(Rectangle())
            }.buttonStyle(PressScaleStyle(scale: 0.86))
                .padding(-11)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
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
    let onReassign: () -> Void
    let onCopy: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(speaker.map(ConversationTint.name) ?? ConversationText.render("[\(utterance.speakerID)]", speakers: []))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(speaker.map(ConversationTint.color) ?? ConversationTint.blue)
                Text(ConversationTint.clock(utterance.start)).font(.caption).foregroundStyle(Color.paplySecondaryText)
            }
            Text(utterance.text).foregroundStyle(Color.paplyText).multilineTextAlignment(.leading)
            if utterance.uncertain {
                Label("Person nicht sicher", systemImage: "questionmark.circle").font(.caption).foregroundStyle(Color.paplySecondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Andere Person …", systemImage: "person.crop.circle", action: onReassign)
            Button("Text kopieren", systemImage: "doc.on.doc", action: onCopy)
        }
        .accessibilityAction(named: "Andere Person …", onReassign)
        .accessibilityAction(named: "Text kopieren", onCopy)
    }
}

#Preview("Detail") { NavigationStack { ConversationDetailPreview(item: ConversationsPreviewData.phone) }.preferredColorScheme(.dark) }
#Preview("Aufgabe") { ConversationTaskRow(task: ConversationsPreviewData.phone.tasks[0], recordedAt: .now, onToggle: {}).padding().background(PaplyBackground()).preferredColorScheme(.dark) }
#Preview("Beitrag") {
    ConversationUtteranceRow(utterance: ConversationsPreviewData.utterances[0], speaker: ConversationsPreviewData.phone.conversation.speakers[0], onReassign: {}, onCopy: {})
        .background(PaplyBackground()).preferredColorScheme(.dark)
}
