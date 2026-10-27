import PaplyKit
import SwiftUI
import UIKit

// Gedanken-Detail (KONZEPT §3.2): ein Lesedokument wie in Notizen, kein Formular.
// Themen-Pille · Datum · Titel · ggf. Hinweis-Band · Text · Aufgaben · Verwandt · Original.
// Tippen auf Titel/Text bearbeitet an Ort und Stelle; gespeichert wird beim Verlassen bzw. „Fertig“.

struct ThoughtDetailView: View {
    let id: String
    var focusTask: String?

    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss

    @State private var lastKnown: Thought?
    @State private var titleDraft = ""
    @State private var textDraft = ""
    @State private var editingTitle = false
    @State private var editingText = false
    @State private var newTaskDraft = ""
    @State private var addingTask = false
    @State private var editingTaskID: String?
    @State private var taskDraft = ""
    @State private var showLinkPicker = false
    @State private var confirmDelete = false
    @State private var highlightTask: String?
    @State private var leaving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, text, newTask, task(String) }

    private var thought: Thought? { model.thought(id) ?? (leaving ? lastKnown : nil) }
    private var isEditing: Bool { editingTitle || editingText || addingTask || editingTaskID != nil }

    var body: some View {
        Group {
            if let thought {
                document(thought)
            } else {
                ContentUnavailableView("Gedanke gelöscht", systemImage: "trash",
                                       description: Text("Er liegt unter „Zuletzt gelöscht“."))
                    .foregroundStyle(Color.paplyText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PaplyBackground())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showLinkPicker) {
            LinkPickerSheet(thoughtID: id)
        }
        .confirmationDialog("Gedanken löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteThought() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Er liegt danach 30 Tage unter „Zuletzt gelöscht“.")
        }
        .onAppear { lastKnown = model.thought(id) }
        .onChange(of: model.thought(id)) { _, new in
            if let new { lastKnown = new }
        }
        .onDisappear { commitAll() }
    }

    // MARK: Dokument

    private func document(_ thought: Thought) -> some View {
        ScrollViewReader { proxy in
            List {
                header(thought)
                tasksSection(thought)
                relatedSection(thought)
                ThoughtOriginalSection(source: model.source(thought.id))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PaplyBackground())
            .environment(\.defaultMinListRowHeight, 10)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 40, for: .scrollContent)
            .task(id: focusTask) {
                guard let focusTask else { return }
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(PaplyMotion.smooth(reduce)) { proxy.scrollTo(focusTask, anchor: .center) }
                highlightTask = focusTask
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.6)) { highlightTask = nil }
            }
        }
    }

    @ViewBuilder
    private func header(_ thought: Thought) -> some View {
        let topic = model.topic(thought.topicId)
        // Themen-Pille und Datum in einer Zeile (bei wenig Platz untereinander)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                topicButton(thought, topic: topic)
                Spacer(minLength: 8)
                dateText(thought)
            }
            VStack(alignment: .leading, spacing: 8) {
                topicButton(thought, topic: topic)
                dateText(thought)
            }
        }
        .docRow(top: 4, bottom: 12)

        // Titel
        Group {
            if editingTitle {
                TextField("Titel", text: $titleDraft, axis: .vertical)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
            } else {
                Text(thought.displayTitle)
                    .contentTransition(.opacity)
                    .shimmer(thought.isProcessing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginTitle(thought) }
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(thought.state == .done ? "Tippen zum Bearbeiten" : "")
            }
        }
        .font(.paplyTitle(.title2))
        .foregroundStyle(Color.paplyText)
        .docRow(bottom: 10)

        // Hinweis-Band (nur bei Zustand ≠ fertig bzw. nicht geordnet)
        if thought.isProcessing {
            StatusBand(icon: .sparkles, text: "Wird geordnet …", tint: ThoughtTint.mint, shimmer: true)
                .docRow(bottom: 14)
        } else if let note = thought.stateNote {
            StatusBand(icon: note.icon, text: note.text, tint: note.tint == .paplyBeak ? .paplyBeak : ThoughtTint.mint,
                       actionTitle: note.actionTitle) {
                perform(note.action, thought)
            }
            .docRow(bottom: 14)
        }

        // Text
        Group {
            if editingText {
                TextField("Text", text: $textDraft, axis: .vertical)
                    .focused($focus, equals: .text)
                    .font(.body)
                    .lineSpacing(4)
            } else if let text = thought.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginText(thought) }
                    .accessibilityHint(thought.state == .done ? "Tippen zum Bearbeiten" : "")
            } else if let raw = model.source(thought.id)?.text, !raw.isEmpty {
                Text(raw)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(Color.paplySecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                placeholderLines(thought.isProcessing)
            }
        }
        .foregroundStyle(Color.paplyText.opacity(0.92))
        .docRow(bottom: 22)
        .id("text")
    }

    private func placeholderLines(_ processing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([1.0, 0.92, 0.6], id: \.self) { width in
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 12)
                    .containerRelativeFrame(.horizontal) { length, _ in length * width * 0.86 }
            }
        }
        .shimmer(processing)
        .accessibilityLabel(processing ? "Text wird geordnet" : "Kein Text")
    }

    // MARK: Aufgaben

    @ViewBuilder
    private func tasksSection(_ thought: Thought) -> some View {
        if !thought.tasks.isEmpty || addingTask {
            sectionLabel("Aufgaben")
            ForEach(thought.tasks) { task in
                taskRow(task, thought: thought)
                    .id(task.id)
                    .listRowBackground(highlightTask == task.id ? ThoughtTint.mint.opacity(0.14) : Color.clear)
            }
            if addingTask {
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(Color.paplyText.opacity(0.35))
                        .frame(minWidth: 28)
                    TextField("Neue Aufgabe", text: $newTaskDraft)
                        .focused($focus, equals: .newTask)
                        .submitLabel(.done)
                        .onSubmit { commitNewTask(keepAdding: true) }
                        .foregroundStyle(Color.paplyText)
                }
                .docRow(top: 4, bottom: 4)
            } else if thought.state == .done {
                Button {
                    beginNewTask()
                } label: {
                    HStack(spacing: 12) {
                        LucideImage(.circlePlus, size: 22, stroke: 1.8, relativeTo: .body)
                            .frame(minWidth: 28)
                        Text("Aufgabe")
                            .font(.body.weight(.medium))
                    }
                    .foregroundStyle(Color.paplyGreenBright)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .docRow(top: 4, bottom: 4)
            }
            Color.clear.frame(height: 14).docRow()
        }
    }

    @ViewBuilder
    private func taskRow(_ task: ThoughtTask, thought: Thought) -> some View {
        if editingTaskID == task.id {
            HStack(spacing: 12) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(Color.paplyText.opacity(0.5))
                    .frame(minWidth: 28)
                TextField("Aufgabe", text: $taskDraft, axis: .vertical)
                    .focused($focus, equals: .task(task.id))
                    .submitLabel(.done)
                    .onSubmit { commitTask() }
                    .foregroundStyle(Color.paplyText)
            }
            .docRow(top: 4, bottom: 4, background: false)
        } else {
            TaskLine(task: task) {
                withAnimation(PaplyMotion.smooth(reduce)) { model.toggleTask(thought.id, task.id) }
            }
            .contentShape(Rectangle())
            .onTapGesture { beginTask(task) }
            .docRow(top: 4, bottom: 4, background: false)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTask(thought.id, task.id) }
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .contextMenu {
                ShareLink(item: task.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                Button { beginTask(task) } label: { Label("Bearbeiten", systemImage: "pencil") }
                Button(role: .destructive) {
                    withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTask(thought.id, task.id) }
                } label: { Label("Löschen", systemImage: "trash") }
            }
        }
    }

    // MARK: Verwandt

    @ViewBuilder
    private func relatedSection(_ thought: Thought) -> some View {
        let related = model.linked(thought.id)
        if !related.isEmpty {
            sectionLabel("Verwandt")
            ForEach(related, id: \.thought.id) { item in
                Button {
                    commitAll()
                    nav.path.append(.thought(item.thought.id))
                } label: {
                    RelatedRow(other: item.thought, link: item.link, incoming: item.incoming)
                }
                .buttonStyle(.plain)
                .docRow(top: 6, bottom: 6)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation(PaplyMotion.smooth(reduce)) {
                            if item.incoming {
                                model.removeLink(item.thought.id, target: thought.id)
                            } else {
                                model.removeLink(thought.id, target: item.thought.id)
                            }
                        }
                    } label: {
                        Label("Verbindung lösen", systemImage: "link.badge.plus")
                    }
                }
            }
            Color.clear.frame(height: 14).docRow()
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paplyTitle(.subheadline, weight: .semibold))
            .foregroundStyle(Color.paplySecondaryText)
            .docRow(top: 8, bottom: 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func topicButton(_ thought: Thought, topic: Topic?) -> some View {
        Button {
            nav.topicPicker = SheetID(id: thought.id)
        } label: {
            TopicPill(topic: topic)
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .fixedSize()
        .accessibilityLabel(topic.map { "Thema \($0.title), ändern" } ?? "Kein Thema, Thema wählen")
    }

    private func dateText(_ thought: Thought) -> some View {
        Text(dateLine(thought))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Color.paplySecondaryText)
            .lineLimit(1)
            .fixedSize()
    }

    /// „Di., 27. Okt. · 08:14 · 1:12 Min.“
    private func dateLine(_ thought: Thought) -> String {
        var parts = [ThoughtDate.shortDay.string(from: thought.createdAt), Format.time.string(from: thought.createdAt)]
        if thought.durationMs > 0 { parts.append(ThoughtDate.duration(ms: thought.durationMs)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Leiste oben

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { commitAll() }
                    .fontWeight(.semibold)
            }
        } else if let thought {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: ThoughtShare.text(thought)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Teilen")
                Menu {
                    Button {
                        ThoughtClipboard.copy(thought)
                        nav.show(ThoughtsToast(text: "Kopiert"), reduceMotion: reduce)
                    } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    Button { nav.topicPicker = SheetID(id: thought.id) } label: { Label("Thema ändern", systemImage: "tag") }
                    if thought.state == .done {
                        Button { beginNewTask() } label: { Label("Aufgabe hinzufügen", systemImage: "checklist") }
                    }
                    Button { showLinkPicker = true } label: { Label("Verknüpfen …", systemImage: "link") }
                    if thought.state == .done || thought.state == .needsAttention {
                        Button { model.reorganize(thought.id) } label: { Label("Erneut ordnen", systemImage: "arrow.clockwise") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    Image(systemName: PaplyStyle.usesGlass ? "ellipsis" : "ellipsis.circle")
                }
                .accessibilityLabel("Mehr")
            }
        }
    }

    // MARK: Bearbeiten (owner = user übernimmt das Modell)

    private func beginTitle(_ thought: Thought) {
        guard thought.state == .done else { return }
        commitAll()
        titleDraft = thought.title ?? ""
        editingTitle = true
        focus = .title
    }

    private func beginText(_ thought: Thought) {
        guard thought.state == .done else { return }
        commitAll()
        textDraft = thought.text ?? ""
        editingText = true
        focus = .text
    }

    private func beginNewTask() {
        commitAll()
        newTaskDraft = ""
        addingTask = true
        focus = .newTask
    }

    private func beginTask(_ task: ThoughtTask) {
        commitAll()
        taskDraft = task.text
        editingTaskID = task.id
        focus = .task(task.id)
    }

    private func commitTitle() {
        guard editingTitle else { return }
        editingTitle = false
        let value = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = model.thought(id), !value.isEmpty, value != current.title {
            model.setTitle(id, value)
        }
    }

    private func commitText() {
        guard editingText else { return }
        editingText = false
        let value = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = model.thought(id), value != (current.text ?? "") {
            model.setText(id, value)
        }
    }

    private func commitNewTask(keepAdding: Bool = false) {
        let value = newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            withAnimation(PaplyMotion.smooth(reduce)) { model.addTask(id, text: value) }
        }
        newTaskDraft = ""
        if keepAdding && !value.isEmpty {
            focus = .newTask
        } else {
            addingTask = false
        }
    }

    private func commitTask() {
        guard let taskID = editingTaskID else { return }
        editingTaskID = nil
        let value = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = model.thought(id)?.tasks.first { $0.id == taskID }
        if value.isEmpty {
            withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTask(id, taskID) }
        } else if value != current?.text {
            model.editTask(id, taskID, text: value)
        }
    }

    private func commitAll() {
        commitTitle()
        commitText()
        if addingTask { commitNewTask() }
        commitTask()
        focus = nil
    }

    private func perform(_ action: ThoughtStateNote.Action?, _ thought: Thought) {
        switch action {
        case .enterKey: nav.showSettings = true
        case .retry, .reorganize: model.reorganize(thought.id)
        case nil: break
        }
    }

    private func deleteThought() {
        commitAll()
        leaving = true
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) { token = model.delete(id) }
        dismiss()
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Gelöscht", undo: token, seconds: 4), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Löschen", model: model, token: token)
    }
}

// MARK: - Bausteine

/// Themen-Pille „◆ Paply ▾“
struct TopicPill: View {
    let topic: Topic?

    var body: some View {
        HStack(spacing: 6) {
            if let topic {
                TopicGlyph(key: topic.icon.rawValue, size: 15, stroke: 1.9, relativeTo: .subheadline)
                Text(topic.title)
                    .lineLimit(1)
            } else {
                LucideImage(.tag, size: 15, stroke: 1.9, relativeTo: .subheadline)
                Text("Thema wählen")
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .opacity(0.7)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(topic == nil ? Color.paplySecondaryText : ThoughtTint.mint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(topic == nil ? Color.white.opacity(0.08) : ThoughtTint.mint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(topic == nil ? Color.white.opacity(0.1) : ThoughtTint.mint.opacity(0.22), lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

/// Hinweis-Band unter dem Datum (§3.2, §3.7)
struct StatusBand: View {
    let icon: Lucide
    let text: String
    var tint: Color = ThoughtTint.mint
    var shimmer = false
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        // Knopf rechts, wenn Text und Knopf nebeneinander passen; sonst darunter (keine Silbentrennung)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                glyph
                label.fixedSize()
                Spacer(minLength: 8)
                button
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    glyph
                    label.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                button
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var glyph: some View {
        LucideImage(icon, size: 17, stroke: 2, relativeTo: .subheadline)
            .foregroundStyle(tint)
    }

    private var label: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.paplyText)
            .shimmer(shimmer)
    }

    @ViewBuilder
    private var button: some View {
        if let actionTitle {
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.paplyForest)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.paplyGreenBright))
                .buttonStyle(.borderless)
        }
    }
}

/// Eine Verbindung: Titel · Art · wann · kurzer Grund
struct RelatedRow: View {
    let other: Thought
    let link: ThoughtLink
    let incoming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideImage(.cornerDownRight, size: 17, stroke: 2, relativeTo: .body)
                .foregroundStyle(ThoughtTint.mint.opacity(0.8))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(other.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.paplyText)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(link.kind.label(incoming: incoming))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThoughtTint.mint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ThoughtTint.mint.opacity(0.13)))
                    Text(ThoughtDate.relative.localizedString(for: other.createdAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(Color.paplySecondaryText)
                }
                if !link.reason.isEmpty {
                    Text("„\(link.reason)“")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplySecondaryText)
                        .multilineTextAlignment(.leading)
                } else if link.origin == .user {
                    Text("Von dir verknüpft")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyTertiaryText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.paplyTertiaryText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// Zeile im Lesedokument: ohne Trennlinie, ohne Hintergrund, mit Seitenrand
    func docRow(top: CGFloat = 0, bottom: CGFloat = 0, background: Bool = true) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
            .listRowSeparator(.hidden)
            .modifier(DocRowBackground(clear: background))
    }
}

private struct DocRowBackground: ViewModifier {
    let clear: Bool
    func body(content: Content) -> some View {
        if clear { content.listRowBackground(Color.clear) } else { content }
    }
}
