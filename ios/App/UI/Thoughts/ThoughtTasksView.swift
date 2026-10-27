import PaplyKit
import SwiftUI

// Aufgaben-Sicht (KONZEPT §3.3): schlanke Liste über alle Gedanken. Abschnitte „Offen“ und
// „Erledigt“ (zugeklappt, letzte 30 Tage). Kein Aufgabenmanager: keine Erinnerungen, keine Prioritäten.

/// Eine Aufgabe: Kreis · Text · darunter klein Thema + Gedanke · rechts Zeitpunkt im Wortlaut
struct TaskLine: View {
    let task: ThoughtTask
    /// Themen-Symbol + Titel des Gedankens (nur in der Sammelsicht)
    var subtitle: (icon: TopicIcon?, text: String)?
    /// sichtbar erledigt, aber noch nicht übernommen (1,2 s in der Aufgaben-Sicht)
    var pendingDone = false
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce

    private var shownDone: Bool { task.done || pendingDone }
    private var overdue: Bool { !shownDone && (task.dueAt.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: shownDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(shownDone ? Color.paplyGreenBright : Color.paplyText.opacity(0.5))
                    .symbolEffect(.bounce, value: shownDone)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shownDone ? "Erledigt" : "Offen")
            .accessibilityHint(shownDone ? "Tippen öffnet die Aufgabe wieder" : "Tippen hakt die Aufgabe ab")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .font(.body)
                    .foregroundStyle(shownDone ? Color.paplySecondaryText : Color.paplyText)
                    .strikethrough(shownDone, color: Color.paplySecondaryText)
                    .animation(PaplyMotion.smooth(reduce), value: shownDone)
                if let subtitle {
                    HStack(spacing: 4) {
                        if let icon = subtitle.icon {
                            Image(systemName: icon.systemImage)
                                .imageScale(.small)
                                .foregroundStyle(ThoughtTint.mint.opacity(0.85))
                        }
                        Text(subtitle.text)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.paplySecondaryText)
                }
            }
            Spacer(minLength: 8)
            if let hint = task.dueHint, !hint.isEmpty {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(overdue ? Color.paplyBeak : Color.paplySecondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        // Haptik (§4): abhaken leicht, wieder öffnen Auswahl
        .sensoryFeedback(trigger: shownDone) { _, new in new ? .impact(weight: .light) : .selection }
        .accessibilityElement(children: .combine)
    }
}

/// Inhalt der Liste, wenn der Chip „Aufgaben“ gewählt ist
struct TaskSections: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var showDone = false
    /// abgehakt, aber noch nicht übernommen (rückgängig durch Tippen innerhalb von 1,2 s)
    @State private var pending: [String: Task<Void, Never>] = [:]
    @State private var editing: (thoughtID: String, task: ThoughtTask)?
    @State private var editDraft = ""

    var body: some View {
        let open = model.openTasks(topicID: nil)
        let done = model.doneTasks(days: 30)
        let topics = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        if open.isEmpty && pending.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Keine offenen Aufgaben", systemImage: "checklist")
                } description: {
                    Text("Paply erkennt sie, wenn du sagst: „Ich muss …“ oder „Nicht vergessen …“.")
                }
                .foregroundStyle(Color.paplyText)
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(open, id: \.task.id) { item in
                    row(item, topic: topics[item.thought.topicId ?? ""])
                }
            } header: {
                header("Offen", count: open.count)
            }
            .alert("Aufgabe bearbeiten", isPresented: editAlert) { editAlertActions }
        }

        if !done.isEmpty {
            Section {
                if showDone {
                    ForEach(done, id: \.task.id) { item in
                        row(item, topic: topics[item.thought.topicId ?? ""])
                    }
                }
            } header: {
                Button {
                    withAnimation(PaplyMotion.smooth(reduce)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Erledigt")
                        Text("\(done.count)").foregroundStyle(Color.paplyTertiaryText).monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .rotationEffect(.degrees(showDone ? 90 : 0))
                            .foregroundStyle(Color.paplyTertiaryText)
                        Spacer()
                    }
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.paplyText)
                    .textCase(nil)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(showDone ? "aufgeklappt" : "zugeklappt")
            } footer: {
                if showDone {
                    Text("Erledigte Aufgaben der letzten 30 Tage.")
                }
            }
        }
    }

    private var editAlert: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    @ViewBuilder
    private var editAlertActions: some View {
        TextField("Aufgabe", text: $editDraft)
        Button("Abbrechen", role: .cancel) {}
        Button("Sichern") {
            let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if let editing, !text.isEmpty {
                model.editTask(editing.thoughtID, editing.task.id, text: text)
            }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)").foregroundStyle(Color.paplyTertiaryText).monospacedDigit()
        }
        .font(.title3.weight(.bold))
        .foregroundStyle(Color.paplyText)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: (task: ThoughtTask, thought: Thought), topic: Topic?) -> some View {
        TaskLine(task: item.task, subtitle: (topic?.icon, item.thought.displayTitle),
                 pendingDone: pending[item.task.id] != nil) {
            toggle(item)
        }
        .contentShape(Rectangle())
        .onTapGesture { nav.path.append(.thought(item.thought.id, task: item.task.id)) }
        .listRowBackground(Color.paplyRow)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTask(item.thought.id, item.task.id) }
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .contextMenu {
            ShareLink(item: item.task.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
            Button {
                editDraft = item.task.text
                editing = (item.thought.id, item.task)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Button {
                nav.path.append(.thought(item.thought.id, task: item.task.id))
            } label: {
                Label("Gedanken öffnen", systemImage: "text.bubble")
            }
            Divider()
            Button(role: .destructive) {
                withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTask(item.thought.id, item.task.id) }
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    /// Kreis tippen: Füllung + Durchstreichen sofort, nach 1,2 s gleitet die Zeile zu „Erledigt“.
    /// Erneutes Tippen innerhalb der 1,2 s macht es rückgängig. Erledigte öffnen sofort wieder.
    private func toggle(_ item: (task: ThoughtTask, thought: Thought)) {
        let key = item.task.id
        if item.task.done {
            withAnimation(PaplyMotion.smooth(reduce)) { model.toggleTask(item.thought.id, key) }
            return
        }
        if let running = pending[key] {
            running.cancel()
            pending[key] = nil
            return
        }
        let thoughtID = item.thought.id
        let store = model
        let smooth = PaplyMotion.smooth(reduce)
        pending[key] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(smooth) {
                store.toggleTask(thoughtID, key)
                pending[key] = nil
            }
        }
    }
}
