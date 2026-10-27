import PaplyKit
import SwiftUI
import UIKit

// Tab „Gedanken“ (KONZEPT §2, §3.1): großer Titel, Chips, Liste wie Apple Notizen. Kompakter Kopf:
// Suche als Lupe in der Leiste (eigene Seite), Aufnahme-Knopf in der unteren Werkzeugleiste – so
// verdeckt er nie Zeilen. Viele Gedanken: List lädt Zeilen erst beim Scrollen, Abschnitte entstehen
// in einem Durchlauf ohne Kalender je Zeile.

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
                    case .search:
                        ThoughtsSearchView()
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
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var topicAction: TopicAction?

    var body: some View {
        content
            .background(PaplyBackground())
            .navigationTitle("Gedanken")
            .toolbar { toolbar }
            .toolbar { bottomBar }
            .topicActions($topicAction)
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
        if model.thoughts.isEmpty {
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
            if SetupGuide.shared.isVisible(model: model) {
                Section {
                    SetupCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                            ThoughtsSectionHeader(title: "Offen")
                        }
                    }
                    thoughtSections(model.thoughts.filter { $0.topicId == id }, topics: topicsByID, showTopic: false, thisYear: thisYear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(10)
        .contentMargins(.top, 2, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .animation(PaplyMotion.bouncy(reduce), value: model.thoughts.first?.id)
    }

    @ViewBuilder
    private func thoughtSections(_ thoughts: [Thought], topics: [String: Topic], showTopic: Bool, thisYear: Int) -> some View {
        let sections = ThoughtSections.make(thoughts)
        ForEach(sections) { section in
            Section {
                ForEach(section.thoughts) { thought in
                    ThoughtListRow(thought: thought, topic: topics[thought.topicId ?? ""], showTopic: showTopic,
                                   time: section.timeLabel(thought.createdAt, thisYear: thisYear),
                                   zoomSource: flow.zoomSource == thought.id)
                }
            } header: {
                ThoughtsSectionHeader(title: section.title)
            }
        }
    }

    // MARK: Chips

    private var chips: some View {
        // Themen nach letzter Aktivität: ein Durchlauf über die (neueste zuerst sortierten) Gedanken
        var order: [String: Int] = [:]
        for thought in model.thoughts {
            if let id = thought.topicId, order[id] == nil { order[id] = order.count }
        }
        let selectedID: String? = if case .topic(let id) = nav.filter { id } else { nil }
        let active = model.topics
            .filter { model.showsAsChip($0) || $0.id == selectedID }
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

    // MARK: Leisten

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                nav.path.append(.search)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Suchen")
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

    /// Unten wie in Notizen: Anzahl in der Mitte, Aufnahme-Knopf rechts (§3.1, zweiter Weg neben dem Knopf
    /// im Sperrbildschirm). Als Werkzeugleiste verdeckt er keine Zeilen.
    @ToolbarContentBuilder
    private var bottomBar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            // iOS 18: Leiste über der Tab-Leiste mit Anzahl wie in Notizen. iOS 26 setzt den Knopf
            // neben die schwebende Tab-Leiste – dort hätte der Text keinen Platz.
            if !PaplyStyle.usesGlass {
                Text(countText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.paplySecondaryText)
                    .monospacedDigit()
                    .fixedSize()
                Spacer()
            }
            CaptureToolbarButton {
                flow.openBig(source: CaptureFlow.fabSource)
            }
        }
    }

    private var countText: String {
        switch nav.filter {
        case .all:
            let n = model.thoughts.count
            return n == 1 ? "1 Gedanke" : "\(n) Gedanken"
        case .tasks:
            let n = model.openTasks(topicID: nil).count
            return n == 1 ? "1 offene Aufgabe" : "\(n) offene Aufgaben"
        case .topic(let id):
            let n = model.count(of: id)
            return n == 1 ? "1 Gedanke" : "\(n) Gedanken"
        }
    }
}

/// Aufnahme-Knopf der unteren Leiste: p-Kopf auf Grün (iOS 26: grün getöntes Glas).
struct CaptureToolbarButton: View {
    let action: () -> Void
    @Environment(\.captureZoom) private var zoom

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                if PaplyStyle.usesGlass {
                    Button(action: action) {
                        PaplyMark(monochrome: .paplyForest)
                            .frame(width: 19, height: 21)
                            .offset(x: -0.5)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.paplyGreenBright)
                } else {
                    classic
                }
            } else {
                classic
            }
        }
        .captureZoomSource(CaptureFlow.fabSource, in: zoom)
        .accessibilityLabel("Gedanke aufnehmen")
        .accessibilityHint("Öffnet die Aufnahme. Paply ordnet den Gedanken danach.")
    }

    private var classic: some View {
        Button(action: action) {
            PaplyMark(monochrome: .paplyForest)
                .frame(width: 17, height: 19)
                .offset(x: -0.5)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.paplyGreenBright))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Abschnittskopf der Listen: SF Rounded, ruhig, eng am Inhalt
struct ThoughtsSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                Text("\(count)").foregroundStyle(Color.paplyTertiaryText).monospacedDigit()
            }
        }
        .font(.paplyTitle(.title3, weight: .semibold))
        .foregroundStyle(Color.paplyText)
        .textCase(nil)
        .padding(.top, -6)
        .padding(.bottom, -2)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Suche (§3.1) als eigene Seite hinter der Lupe

struct ThoughtsSearchView: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var presented = false

    var body: some View {
        @Bindable var nav = nav
        let query = nav.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if query.isEmpty {
                topicShortcuts
            } else {
                results(query)
            }
        }
        .background(PaplyBackground())
        .navigationTitle("Suchen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $nav.searchText, isPresented: $presented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Gedanken durchsuchen")
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            presented = true
        }
        .onDisappear { nav.searchText = "" }
    }

    /// Leer: Themen als schnelle Wege
    private var topicShortcuts: some View {
        let topics = model.topics.filter { model.showsAsChip($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return List {
            if !topics.isEmpty {
                Section {
                    ForEach(topics) { topic in
                        Button { open(topic) } label: {
                            HStack(spacing: 12) {
                                TopicBadge(icon: topic.icon, size: 30)
                                Text(topic.title).foregroundStyle(Color.paplyText)
                                Spacer()
                                Text("\(model.count(of: topic.id))")
                                    .monospacedDigit()
                                    .foregroundStyle(Color.paplyTertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Color.paplyRow)
                    }
                } header: {
                    ThoughtsSectionHeader(title: "Themen")
                } footer: {
                    Text("Sucht in Titel, Text, Rohtext, Aufgaben und Themen – auf dem iPhone, ohne Netz.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func results(_ query: String) -> some View {
        let hits = model.search(query)
        if hits.isEmpty {
            ContentUnavailableView.search(text: query)
                .foregroundStyle(Color.paplyText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let byID = Dictionary(model.thoughts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let topicsByID = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let topicHits = model.topics.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            List {
                if !topicHits.isEmpty {
                    Section {
                        ForEach(topicHits.prefix(3)) { topic in
                            Button { open(topic) } label: {
                                HStack(spacing: 10) {
                                    TopicGlyph(key: topic.icon.rawValue, size: 17)
                                        .foregroundStyle(ThoughtTint.mint)
                                    Text("Thema: \(topic.title)").foregroundStyle(Color.paplyText)
                                }
                            }
                            .listRowBackground(Color.paplyRow)
                        }
                    }
                }
                Section {
                    ForEach(hits) { hit in
                        if let thought = byID[hit.thoughtID] {
                            ThoughtListRow(thought: thought, topic: topicsByID[thought.topicId ?? ""], showTopic: true,
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
            .listSectionSpacing(14)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func open(_ topic: Topic) {
        nav.searchText = ""
        presented = false
        nav.filter = .topic(topic.id)
        nav.path = []
    }
}
