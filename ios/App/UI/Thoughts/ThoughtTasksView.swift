import PaplyKit
import SwiftUI

// Aufgaben-Sicht (KONZEPT §3.3): schlanke Liste über alle Gedanken. Abschnitte „Offen“ und
// „Erledigt“ (zugeklappt, letzte 30 Tage). Kein Aufgabenmanager: keine Erinnerungen, keine Prioritäten.
// Abhaken überall gleich (TaskCheckoff): Kreis füllt sich sofort, nach 1,2 s gleitet die Aufgabe aus den
// offenen Listen. Erneutes Tippen in der Zeit macht es rückgängig.

/// Abgehakt, aber noch nicht übernommen – geteilt von Leiste „Offen“, Karten, Panel und Aufgabenliste,
/// damit dieselbe Aufgabe überall gleich aussieht.
@MainActor
@Observable
final class TaskCheckoff {
    private(set) var pending: Set<String> = []
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]

    func isShownDone(_ task: ThoughtTask) -> Bool { task.done || pending.contains(task.id) }

    func toggle(_ task: ThoughtTask, thoughtID: String, model: ThoughtsModel, reduceMotion: Bool) {
        let key = task.id
        if task.done {
            withAnimation(PaplyMotion.smooth(reduceMotion)) { model.toggleTask(thoughtID, key) }
            return
        }
        if let running = timers[key] {
            running.cancel()
            timers[key] = nil
            withAnimation(PaplyMotion.smooth(reduceMotion)) { _ = pending.remove(key) }
            return
        }
        withAnimation(PaplyMotion.smooth(reduceMotion)) { _ = pending.insert(key) }
        let smooth = PaplyMotion.smooth(reduceMotion)
        timers[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            withAnimation(smooth) {
                model.toggleTask(thoughtID, key)
                self.pending.remove(key)
            }
            self.timers[key] = nil
        }
    }
}

/// Runder Haken wie im Entwurf: Ring, beim Abhaken grün gefüllt mit Haken (Bouncy)
struct TaskCheckCircle: View {
    let done: Bool
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduce
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let s = size * min(scale, 1.6)
        ZStack {
            Circle()
                .strokeBorder(done ? Color.clear : Color.paplyText.opacity(0.42), lineWidth: 1.6)
                .background(Circle().fill(done ? Color.paplyGreenBright : Color.clear))
            LucideImage(.check, size: s * 0.62, stroke: 3.4, scales: false)
                .foregroundStyle(Color.paplyForest)
                .scaleEffect(done ? 1 : 0.2)
                .opacity(done ? 1 : 0)
        }
        .frame(width: s, height: s)
        .animation(PaplyMotion.bouncy(reduce), value: done)
        .accessibilityHidden(true)
    }
}

/// Haken als Knopf mit großer Trefferfläche (44 pt), Haptik wie in der Liste
struct TaskCheckButton: View {
    let task: ThoughtTask
    let thoughtID: String
    var size: CGFloat = 22

    @Environment(ThoughtsModel.self) private var model
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let done = checkoff.isShownDone(task)
        Button {
            checkoff.toggle(task, thoughtID: thoughtID, model: model, reduceMotion: reduce)
        } label: {
            TaskCheckCircle(done: done, size: size)
                .padding(11)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.86))
        .padding(-11)
        .sensoryFeedback(trigger: done) { _, new in new ? .impact(weight: .light) : .selection }
        .accessibilityLabel(done ? "Erledigt: \(task.text)" : "Abhaken: \(task.text)")
        .accessibilityHint(done ? "Tippen öffnet die Aufgabe wieder" : "")
    }
}

/// Eigene Seite „Aufgaben“ (aus „Alle n“ der Leiste „Offen“ und dem Link `thoughts/tasks`)
struct TasksPage: View {
    var body: some View {
        List {
            TaskSections()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(PaplyBackground())
        .navigationTitle("Aufgaben")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Eine Aufgabe: Kreis · Text · darunter klein Thema + Gedanke · rechts Zeitpunkt im Wortlaut
struct TaskLine: View {
    let task: ThoughtTask
    /// Themen-Symbol + Titel des Gedankens (nur in der Sammelsicht)
    var subtitle: (icon: TopicIcon?, text: String)?
    /// Farbe des Themen-Symbols (Themenfarbe)
    var subtitleTint: Color = ThoughtTint.mint
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
                            TopicGlyph(key: icon.rawValue, size: 12, stroke: 1.9, relativeTo: .caption)
                                .foregroundStyle(subtitleTint)
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
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var showDone = false
    @State private var editing: (thoughtID: String, task: ThoughtTask)?
    @State private var editDraft = ""

    var body: some View {
        let open = model.openTasks(topicID: nil)
        let done = model.doneTasks(days: 30)
        let topics = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        if open.isEmpty {
            Section {
                ContentUnavailableView {
                    Label {
                        Text("Keine offenen Aufgaben")
                    } icon: {
                        LucideImage(.listChecks, size: 44, stroke: 1.6, relativeTo: .largeTitle)
                    }
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
                 subtitleTint: TopicPalette.tint(for: topic?.id).ink,
                 pendingDone: checkoff.pending.contains(item.task.id)) {
            checkoff.toggle(item.task, thoughtID: item.thought.id, model: model, reduceMotion: reduce)
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
}
