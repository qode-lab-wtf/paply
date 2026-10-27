import PaplyKit
import SwiftUI
import UIKit

// Reiter „Aufgaben“ (Gedanken | Aufgaben | Diktat): alle Aufgaben aus allen Gedanken auf einer Seite, im Stil von
// Erinnerungen, nur ruhiger. Gruppen: Überfällig · Heute · Demnächst (mit Datum) · Irgendwann (ohne) · Erledigt
// (zugeklappt, letzte 7 Tage; „Alle erledigten“ zeigt den Rest). Gliederung und Reihenfolge: `TaskAgenda`
// (PaplyKit, getestet) – jede offene Aufgabe steht genau einmal da, ohne Obergrenze.
//
// Zeile: Kreis zum Abhaken (TaskCheckoff, 1,2 s) · Text · Plakette in der Themenfarbe mit dem Titel des Gedankens ·
// rechts die Fälligkeit (Wortlaut am Tag der Aufnahme, danach der Tag). Antippen öffnet den Gedanken an der Aufgabe
// (Zoom aus der Zeile), nach rechts wischen hakt ab, nach links wischen löscht (widerrufbar).

/// Kalendertag für Gruppen und Zahl am Reiter: wechselt um Mitternacht, bei neuer Zeitzone und im Vordergrund.
@MainActor
@Observable
final class TaskDay {
    static let shared = TaskDay()

    /// Beginn des heutigen Tages
    private(set) var today = Calendar.current.startOfDay(for: Date())
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Neu prüfen (Vordergrund); ändert nur etwas, wenn ein neuer Tag begonnen hat
    func refresh() {
        let day = Calendar.current.startOfDay(for: Date())
        if day != today { today = day }
    }
}

// MARK: - Reiter

struct TasksTab: View {
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.captureZoom) private var zoom

    var body: some View {
        @Bindable var nav = nav
        NavigationStack(path: $nav.tasksPath) {
            TasksPage()
                .navigationDestination(for: ThoughtsRoute.self) { route in
                    switch route {
                    case .thought(let id, let task, let source):
                        ThoughtDetailView(id: id, focusTask: task)
                            .detailZoom(source, in: zoom)
                    case .search, .topics, .deleted, .buttonGuide:
                        EmptyView()
                    }
                }
        }
        .environment(\.thoughtsStack, .tasks)
        .overlay(alignment: .bottom) { ThoughtsToastHost() }
        .modifier(CaptureInsetBarModifier())
    }
}

/// Zahl am Reiter: überfällige und heutige offene Aufgaben (0 = keine Zahl)
enum TasksBadge {
    @MainActor
    static func count(_ model: ThoughtsModel) -> Int {
        _ = TaskDay.shared.today
        return TaskAgenda.urgentCount(thoughts: model.thoughts)
    }
}

// MARK: - Seite

struct TasksPage: View {
    /// Zoom-Quelle des Aufnahme-Knopfs dieser Seite (eigene Kennung neben der des Reiters Gedanken)
    static let captureSource = "capture.fab.tasks"
    static let emptyCaptureSource = "capture.tasks.empty"

    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(CaptureFlow.self) private var flow
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.captureZoom) private var zoom
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var showDone = TasksPage.debugShowsDone
    @State private var showAllDone = TasksPage.debugShowsAllDone
    @State private var editing: TaskRef?
    @State private var editDraft = ""

    /// Aufgabe zum Bearbeiten (Hinweisfenster)
    private struct TaskRef: Equatable {
        let thoughtID: String
        let taskID: String
    }

    var body: some View {
        _ = TaskDay.shared.today
        let agenda = model.taskAgenda()
        return Group {
            if !model.isLoaded {
                Color.clear
            } else if agenda.openCount == 0 && agenda.allDone.isEmpty {
                empty
            } else {
                list(agenda)
            }
        }
        .background(PaplyBackground())
        .navigationTitle("Aufgaben")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    nav.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Einstellungen")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                CaptureToolbarButton(source: Self.captureSource) {
                    flow.openBig(source: Self.captureSource)
                }
            }
        }
        .alert("Aufgabe bearbeiten", isPresented: editAlert) {
            TextField("Aufgabe", text: $editDraft)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let editing, !text.isEmpty { model.editTask(editing.thoughtID, editing.taskID, text: text) }
            }
        }
    }

    // MARK: Liste

    private func list(_ agenda: TaskAgenda) -> some View {
        ScrollViewReader { proxy in
            List {
                if agenda.openCount == 0 {
                    allDone
                }
                group(.overdue, agenda.overdue)
                group(.today, agenda.today)
                group(.upcoming, agenda.upcoming)
                group(.someday, agenda.someday)
                if !agenda.allDone.isEmpty {
                    doneSection(agenda)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .scrollContentBackground(.hidden)
            .withoutHyphenation()
            #if DEBUG
            .task {
                // Bildschirmfotos: „Erledigt“ aufgeklappt ins Bild holen
                guard Self.debugShowsDone, let last = (showAllDone ? agenda.allDone : agenda.recentlyDone).last else { return }
                try? await Task.sleep(for: .seconds(0.8))
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            #endif
        }
    }

    @ViewBuilder
    private func group(_ group: TaskAgenda.Group, _ items: [TaskAgenda.Item]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    row(item, group: group)
                }
            } header: {
                TasksSectionHeader(title: Self.title(group), count: items.count,
                                   tint: group == .overdue ? Color.paplyBeak : Color.paplyText)
            }
        }
    }

    private static func title(_ group: TaskAgenda.Group) -> String {
        switch group {
        case .overdue: "Überfällig"
        case .today: "Heute"
        case .upcoming: "Demnächst"
        case .someday: "Irgendwann"
        }
    }

    /// Erledigt: zugeklappt; aufgeklappt die letzten 7 Tage, „Alle erledigten“ zeigt den Rest
    private func doneSection(_ agenda: TaskAgenda) -> some View {
        let shown = showAllDone ? agenda.allDone : agenda.recentlyDone
        let older = agenda.allDone.count - agenda.recentlyDone.count
        return Section {
            if showDone {
                if shown.isEmpty {
                    Text("In den letzten 7 Tagen nichts erledigt.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplySecondaryText)
                        .listRowBackground(Color.paplyRow)
                }
                ForEach(shown) { item in
                    row(item, group: nil)
                }
                if !showAllDone, older > 0 {
                    Button {
                        withAnimation(PaplyMotion.smooth(reduce)) { showAllDone = true }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Alle erledigten")
                            Text("\(agenda.allDone.count)")
                                .monospacedDigit()
                                .foregroundStyle(Color.paplyTertiaryText)
                            Spacer()
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.paplyGreenBright)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.paplyRow)
                    .accessibilityHint("Zeigt auch ältere erledigte Aufgaben")
                }
            }
        } header: {
            Button {
                withAnimation(PaplyMotion.smooth(reduce)) {
                    showDone.toggle()
                    if !showDone { showAllDone = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Erledigt")
                    let count = showAllDone ? agenda.allDone.count : agenda.recentlyDone.count
                    if count > 0 {
                        Text("\(count)")
                            .foregroundStyle(Color.paplyTertiaryText)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                        .foregroundStyle(Color.paplyTertiaryText)
                    Spacer()
                }
                .font(.paplyTitle(.title3, weight: .semibold))
                .foregroundStyle(Color.paplyText)
                .textCase(nil)
                .padding(.top, -6)
                .padding(.bottom, -2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(showDone ? "aufgeklappt" : "zugeklappt")
        } footer: {
            if showDone {
                Text(showAllDone ? "Alle erledigten Aufgaben, neueste zuerst." : "Erledigt in den letzten 7 Tagen.")
            }
        }
    }

    private func row(_ item: TaskAgenda.Item, group: TaskAgenda.Group?) -> some View {
        let zoomID = "task:\(item.id)"
        let shownDone = checkoff.isShownDone(item.task)
        return TaskAgendaRow(item: item, group: group)
            .contentShape(Rectangle())
            .onTapGesture { open(item, zoomID: zoomID) }
            .modifier(TaskZoomSource(id: zoomID, namespace: zoom))
            .listRowBackground(Color.paplyRow)
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    checkoff.set(item.task, done: !shownDone, thoughtID: item.thought.id, model: model, reduceMotion: reduce)
                } label: {
                    if shownDone {
                        Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("Erledigt", systemImage: "checkmark")
                    }
                }
                .tint(shownDone ? Color.gray : Color.paplyGreen)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    checkoff.set(item.task, done: !shownDone, thoughtID: item.thought.id, model: model, reduceMotion: reduce)
                } label: {
                    if shownDone {
                        Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("Erledigt", systemImage: "checkmark.circle")
                    }
                }
                Button {
                    editDraft = item.task.text
                    editing = TaskRef(thoughtID: item.thought.id, taskID: item.task.id)
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                Button {
                    open(item, zoomID: nil)
                } label: {
                    Label("Gedanken öffnen", systemImage: "text.bubble")
                }
                ShareLink(item: item.task.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .accessibilityAction { open(item, zoomID: nil) }
            .accessibilityAction(named: shownDone ? "Wieder öffnen" : "Abhaken") {
                checkoff.set(item.task, done: !shownDone, thoughtID: item.thought.id, model: model, reduceMotion: reduce)
            }
            .accessibilityAction(named: "Löschen") { delete(item) }
    }

    private func open(_ item: TaskAgenda.Item, zoomID: String?) {
        nav.tasksPath.append(.thought(item.thought.id, task: item.task.id, zoom: zoom == nil ? nil : zoomID))
    }

    private func delete(_ item: TaskAgenda.Item) {
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) { token = model.deleteTask(item.thought.id, item.task.id) }
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Aufgabe gelöscht", undo: token, seconds: 4), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Aufgabe löschen", model: model, token: token)
    }

    private var editAlert: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    // MARK: Leer

    /// Keine offenen, aber erledigte Aufgaben
    private var allDone: some View {
        Section {
            HStack(spacing: 12) {
                LucideImage(.check, size: 18, stroke: 2.8, relativeTo: .body)
                    .foregroundStyle(Color.paplyForest)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.paplyGreenBright))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alles erledigt")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                    Text("Neue Aufgaben entstehen aus deinen Gedanken.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplySecondaryText)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.paplyRow)
            .accessibilityElement(children: .combine)
        }
    }

    /// Noch nie eine Aufgabe
    private var empty: some View {
        ContentUnavailableView {
            Label {
                Text("Noch keine Aufgaben")
                    .font(.paplyTitle(.title2))
            } icon: {
                LucideImage(.listChecks, size: 46, stroke: 1.6, relativeTo: .largeTitle)
                    .foregroundStyle(ThoughtTint.mint)
            }
        } description: {
            Text("Aufgaben entstehen aus deinen Gedanken. Sag einfach „Ich muss …“ – Paply hält sie hier fest.")
                .withoutHyphenation()
        } actions: {
            Button {
                flow.openBig(source: Self.emptyCaptureSource)
            } label: {
                Text("Gedanke aufnehmen")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.paplyForest)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.paplyGreenBright))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .captureZoomSource(Self.emptyCaptureSource, in: zoom)
        }
        .foregroundStyle(Color.paplyText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Debug

    private static var debugShowsDone: Bool {
        #if DEBUG
        ["tasks-done", "tasks-all-done"].contains(ThoughtsDebug.screen ?? "")
        #else
        false
        #endif
    }

    private static var debugShowsAllDone: Bool {
        #if DEBUG
        ThoughtsDebug.screen == "tasks-all-done"
        #else
        false
        #endif
    }
}

/// Abschnittskopf wie in den übrigen Listen (SF Rounded), „Überfällig“ in Warnfarbe
private struct TasksSectionHeader: View {
    let title: String
    let count: Int
    var tint: Color = .paplyText

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(tint)
            Text("\(count)")
                .foregroundStyle(Color.paplyTertiaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.paplyTitle(.title3, weight: .semibold))
        .textCase(nil)
        .padding(.top, -6)
        .padding(.bottom, -2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Zoom aus der Zeile ins Detail (nur mit Namensraum)
private struct TaskZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Zeile

/// Kreis · Text (volle Breite) · darunter Plakette (Thema + Gedanke) und rechts die Fälligkeit; erledigt: wann
struct TaskAgendaRow: View {
    let item: TaskAgenda.Item
    /// nil = Abschnitt „Erledigt“
    let group: TaskAgenda.Group?

    @Environment(ThoughtsModel.self) private var model
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let done = checkoff.isShownDone(item.task)
        let due = dueText
        let big = typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TaskCheckButton(task: item.task, thoughtID: item.thought.id, size: 22)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.task.text)
                    .font(.body)
                    .foregroundStyle(done ? Color.paplySecondaryText : Color.paplyText)
                    // durchgestrichen nur im Moment des Abhakens; unter „Erledigt“ ruhig grau
                    .strikethrough(done && group != nil, color: Color.paplySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(PaplyMotion.smooth(reduce), value: done)
                if big {
                    TopicPlaque(thought: item.thought, topic: model.topic(item.thought.topicId))
                    if let due { dueLabel(due) }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        TopicPlaque(thought: item.thought, topic: model.topic(item.thought.topicId))
                        Spacer(minLength: 0)
                        if let due {
                            dueLabel(due)
                                .fixedSize()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Öffnet den Gedanken")
    }

    private func dueLabel(_ due: (text: String, color: Color)) -> some View {
        Text(due.text)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(due.color)
            .lineLimit(1)
    }

    /// Fälligkeit; im Abschnitt „Erledigt“ wann erledigt
    private var dueText: (text: String, color: Color)? {
        guard let group else {
            guard let doneAt = item.task.doneAt else { return nil }
            return (ThoughtDate.card(doneAt), Color.paplyTertiaryText)
        }
        guard let label = TaskDueLabel.make(task: item.task, recordedAt: item.thought.createdAt) else { return nil }
        let text: String?
        switch (group, label) {
        case (.today, .today(let time)):
            // unter „Heute“ steht „Heute“ schon im Kopf – nur die Uhrzeit
            text = time.map { Format.time.string(from: $0) }
        case (.today, .wording(let wording)) where wording.lowercased() == "heute":
            text = nil
        default:
            text = TaskDueText.text(label)
        }
        guard let text else { return nil }
        let color: Color = switch group {
        case .overdue: .paplyBeak
        case .today: ThoughtTint.mint
        case .upcoming, .someday: .paplySecondaryText
        }
        return (text, color)
    }
}

/// Fälligkeit als Text: „morgen“ (Wortlaut), „Heute, 15:00“, „Morgen“, „Gestern“, „Freitag“, „Di., 3. Nov.“
enum TaskDueText {
    static func text(_ label: TaskDueLabel, now: Date = Date()) -> String {
        func time(_ date: Date?) -> String { date.map { ", " + Format.time.string(from: $0) } ?? "" }
        switch label {
        case .wording(let wording):
            return wording
        case .today(let at):
            return "Heute" + time(at)
        case .tomorrow(let at):
            return "Morgen" + time(at)
        case .yesterday(let at):
            return "Gestern" + time(at)
        case .weekday(let date, let at):
            return ThoughtDate.weekday.string(from: date) + time(at)
        case .date(let date, let at):
            let calendar = Calendar.current
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return (sameYear ? ThoughtDate.shortDay.string(from: date) : ThoughtDate.dayMonthYear.string(from: date)) + time(at)
        }
    }
}

/// Kleine Plakette in der Themenfarbe: Bild bzw. Symbol des Themas und der Titel des Gedankens
struct TopicPlaque: View {
    let thought: Thought
    let topic: Topic?

    var body: some View {
        let tint = TopicPalette.tint(for: topic?.id)
        let hasImage = TopicImages.shared.hasImage(for: topic?.id)
        HStack(spacing: 5) {
            if let topic {
                TopicMark(topicID: topic.id, icon: topic.icon, size: 11, stroke: 2.1, relativeTo: .caption, imageScale: 1.45)
            }
            Text(thought.displayTitle)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(topic == nil ? Color.paplySecondaryText : tint.ink)
        .padding(.leading, hasImage ? 2.5 : 7)
        .padding(.trailing, 8)
        .padding(.vertical, hasImage ? 2.5 : 3.5)
        .background(Capsule().fill(topic == nil ? Color.white.opacity(0.07) : tint.badge))
        .overlay(Capsule().strokeBorder(topic == nil ? Color.white.opacity(0.08) : tint.stroke, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(topic.map { "\($0.title), \(thought.displayTitle)" } ?? thought.displayTitle)
    }
}
