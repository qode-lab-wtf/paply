import PaplyKit
import SwiftUI

// Tab „Gedanken“ (KONZEPT §2, §3.1): großer Titel, Suche, Chips, Liste wie Apple Notizen,
// Aufnahme-Knopf unten rechts. Viele Gedanken: List lädt Zeilen erst beim Scrollen, Abschnitte
// entstehen in einem Durchlauf ohne Kalender je Zeile.

struct ThoughtsTab: View {
    @Environment(ThoughtsNav.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        NavigationStack(path: $nav.path) {
            ThoughtsHome()
                .navigationDestination(for: ThoughtsRoute.self) { route in
                    switch route {
                    case .thought(let id, let task):
                        ThoughtDetailView(id: id, focusTask: task)
                    case .topics:
                        TopicsEditView()
                    case .deleted:
                        RecentlyDeletedView()
                    case .buttonGuide:
                        ThoughtButtonGuideView()
                    }
                }
        }
        .sheet(item: $nav.topicPicker) { item in
            TopicPickerSheet(thoughtID: item.id)
        }
        .overlay(alignment: .bottom) { ThoughtsToastHost() }
        .modifier(CaptureInsetBarModifier())
    }
}

struct ThoughtsHome: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(CaptureFlow.self) private var flow
    @Environment(\.captureZoom) private var zoom
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var topicAction: TopicAction?
    @State private var deletePulse = 0
    private let session = SessionController.shared

    var body: some View {
        @Bindable var nav = nav
        content
            .background(PaplyBackground())
            .navigationTitle("Gedanken")
            .toolbar { toolbar }
            .searchable(text: $nav.searchText, isPresented: $nav.searchPresented, prompt: "Gedanken durchsuchen")
            .searchSuggestions { suggestions }
            .overlay(alignment: .bottomTrailing) { captureButton }
            .topicActions($topicAction)
            .sensoryFeedback(.impact(weight: .medium), trigger: deletePulse)
            .onChange(of: model.topics.map(\.id)) { _, ids in
                // gewähltes Thema gelöscht oder zusammengeführt → zurück zu „Alle“
                if case .topic(let id) = nav.filter, !ids.contains(id) {
                    withAnimation(PaplyMotion.smooth(reduce)) { nav.filter = .all }
                }
            }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        let query = nav.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            searchResults(query)
        } else if model.thoughts.isEmpty {
            ThoughtsEmptyState(
                setup: { nav.path.append(.buttonGuide) },
                tryIt: { flow.openBig() }
            )
        } else {
            list
        }
    }

    private var list: some View {
        let topicsByID = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let thisYear = Calendar.current.component(.year, from: Date())
        return List {
            Section {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if session.status == .interrupted {
                Section { MicOffHint() }
                    .listRowBackground(Color.paplyRow)
            }
            switch nav.filter {
            case .all:
                thoughtSections(model.thoughts, topics: topicsByID, showTopic: true, thisYear: thisYear)
            case .tasks:
                TaskSections()
            case .topic(let id):
                if let topic = topicsByID[id] {
                    Section {
                        TopicHeader(topic: topic, count: model.count(of: id)) { topicAction = $0 }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    let open = model.openTasks(topicID: id)
                    if !open.isEmpty {
                        Section {
                            TopicOpenTasks(items: open) { task, thought in
                                withAnimation(PaplyMotion.smooth(reduce)) { model.toggleTask(thought.id, task.id) }
                            } onOpen: { task, thought in
                                nav.path.append(.thought(thought.id, task: task.id))
                            }
                        } header: {
                            sectionHeader("Offen")
                        }
                    }
                    thoughtSections(model.thoughts.filter { $0.topicId == id }, topics: topicsByID, showTopic: false, thisYear: thisYear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 92, for: .scrollContent)
        .animation(PaplyMotion.bouncy(reduce), value: model.thoughts.first?.id)
    }

    @ViewBuilder
    private func thoughtSections(_ thoughts: [Thought], topics: [String: Topic], showTopic: Bool, thisYear: Int) -> some View {
        let sections = ThoughtSections.make(thoughts)
        ForEach(sections) { section in
            Section {
                ForEach(section.thoughts) { thought in
                    row(thought, topic: topics[thought.topicId ?? ""], showTopic: showTopic,
                        time: section.timeLabel(thought.createdAt, thisYear: thisYear))
                }
            } header: {
                sectionHeader(section.title)
            }
        }
    }

    private func row(_ thought: Thought, topic: Topic?, showTopic: Bool, time: String, snippet: AttributedString? = nil,
                     highlightedTitle: AttributedString? = nil) -> some View {
        Button {
            nav.path.append(.thought(thought.id))
        } label: {
            ThoughtRow(thought: thought, topic: topic, showTopic: showTopic, time: time, snippet: snippet,
                       highlightedTitle: highlightedTitle)
        }
        .captureZoomSource(thought.id, in: flow.zoomSource == thought.id ? zoom : nil)
        .listRowBackground(Color.paplyRow)
        .modifier(ThoughtRowActions(
            thought: thought,
            onDelete: { delete(thought) },
            onTopic: { nav.topicPicker = SheetID(id: thought.id) },
            onCopy: {
                ThoughtClipboard.copy(thought)
                nav.show(ThoughtsToast(text: "Kopiert"), reduceMotion: reduce)
            },
            onReorganize: { model.reorganize(thought.id) }
        ))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.paplyText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Chips

    private var chips: some View {
        // Themen nach letzter Aktivität: ein Durchlauf über die (neueste zuerst sortierten) Gedanken
        var order: [String: Int] = [:]
        for thought in model.thoughts {
            if let id = thought.topicId, order[id] == nil { order[id] = order.count }
        }
        let active = model.topics
            .filter { model.isActive($0) }
            .sorted { (order[$0.id] ?? .max, $0.title) < (order[$1.id] ?? .max, $1.title) }
        let open = model.openTasks(topicID: nil).count
        let recentlyDone = model.doneTasks(days: 7).count
        return TopicChips(
            topics: active,
            taskCount: open > 0 || recentlyDone > 0 ? open : nil,
            selection: nav.filter,
            onSelect: { nav.filter = $0 },
            onAction: { topicAction = $0 }
        )
    }

    // MARK: Suche (§3.1)

    @ViewBuilder
    private func searchResults(_ query: String) -> some View {
        let hits = model.search(query)
        if hits.isEmpty {
            ContentUnavailableView.search(text: query)
                .foregroundStyle(Color.paplyText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let byID = Dictionary(model.thoughts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let topicsByID = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            List {
                Section {
                    ForEach(hits) { hit in
                        if let thought = byID[hit.thoughtID] {
                            row(thought, topic: topicsByID[thought.topicId ?? ""], showTopic: true,
                                time: ThoughtDate.compact(thought.createdAt),
                                snippet: hit.field == .title
                                    ? SearchHighlight.attributed(thought.previewLine, query: query, color: .paplyText)
                                    : SearchHighlight.attributed(hit, query: query),
                                highlightedTitle: SearchHighlight.attributed(thought.displayTitle, query: query))
                        }
                    }
                } header: {
                    Text(hits.count == 1 ? "1 Treffer" : "\(hits.count) Treffer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplySecondaryText)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let q = nav.searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            ForEach(model.topics.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.prefix(3)) { topic in
                Button {
                    nav.searchText = ""
                    nav.searchPresented = false
                    withAnimation(PaplyMotion.smooth(reduce)) { nav.filter = .topic(topic.id) }
                } label: {
                    Label("Thema: \(topic.title)", systemImage: topic.icon.systemImage)
                        .foregroundStyle(Color.paplyText)
                }
            }
        }
    }

    // MARK: Leiste oben

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button { nav.path.append(.topics) } label: {
                    Label("Themen bearbeiten", systemImage: "square.grid.2x2")
                }
                Button { nav.path.append(.deleted) } label: {
                    Label(model.deleted.isEmpty ? "Zuletzt gelöscht" : "Zuletzt gelöscht (\(model.deleted.count))", systemImage: "trash")
                }
            } label: {
                Image(systemName: PaplyStyle.usesGlass ? "ellipsis" : "ellipsis.circle")
            }
            .accessibilityLabel("Mehr")
            Button {
                nav.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Einstellungen")
        }
    }

    // MARK: Aufnahme-Knopf (§3.1): 60 pt unten rechts, öffnet die große Ansicht per Zoom

    @ViewBuilder
    private var captureButton: some View {
        if flow.bar != .recording, !nav.searchPresented {
            Button {
                flow.openBig(source: CaptureFlow.fabSource)
            } label: {
                PaplyMark(monochrome: .paplyForest)
                    .frame(width: 24, height: 26)
                    .offset(x: -1)
                    .frame(width: 60, height: 60)
                    .paplyGlass(.prominent(.paplyGreenBright), interactive: true, in: Circle())
                    .shadow(color: .black.opacity(PaplyStyle.usesGlass ? 0.15 : 0.35), radius: 14, y: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .captureZoomSource(CaptureFlow.fabSource, in: zoom)
            .padding(.trailing, 20)
            .padding(.bottom, 16)
            .accessibilityLabel("Gedanke aufnehmen")
            .accessibilityHint("Öffnet die Aufnahme. Paply ordnet den Gedanken danach.")
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    // MARK: Aktionen

    private func delete(_ thought: Thought) {
        deletePulse += 1
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) { token = model.delete(thought.id) }
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Gelöscht", undo: token, seconds: 4), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Löschen", model: model, token: token)
    }
}

/// Schmaler Hinweis, wenn der Knopf gerade nicht sofort aufnehmen kann (§2 „Mikro-Status“).
/// Erscheint nur bei unterbrochenem Mikro. Nach Gerätetest S1 ggf. auch bei „aus“, falls der
/// Knopf ohne Sitzung nicht im Hintergrund starten kann.
private struct MicOffHint: View {
    private let session = SessionController.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(Color.paplyBeak)
                .frame(width: 22)
            Text("Mikro ist aus – der Gedanken-Knopf öffnet Paply dann kurz.")
                .font(.subheadline)
                .foregroundStyle(Color.paplyText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Mikro an") {
                session.stopSession(reason: "thoughts-hint")
                Task { await session.startSession(trigger: "thoughts-hint") }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.paplyGreenBright)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
