import PaplyKit
import SwiftUI
import UIKit

// Tab „Gedanken“: Die Startseite ist eine Landkarte der Themen (Entwurf „Landkarte“). Oben nur die Leiste
// „Offen“ mit der nächsten Aufgabe; der Überblick („320 Gedanken · 8 Themen“) steht auf iOS 26 als
// Untertitel unter „Gedanken“, auf iOS 18 in der unteren Leiste (wie in Notizen). Thema antippen → die Karte
// zoomt hinein, das Panel mit den Karten des Themas gleitet hoch (Raststufen wie Apple Karten). Kompakter
// Kopf: Suche als Lupe (eigene Seite), Aufnahme-Knopf in der unteren Werkzeugleiste.

/// Die Landkarte der Themen (Map/ThoughtMapView.swift)
typealias ThoughtMap = ThoughtMapView

struct ThoughtsTab: View {
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.captureZoom) private var zoom
    @State private var checkoff = TaskCheckoff()

    var body: some View {
        @Bindable var nav = nav
        NavigationStack(path: $nav.path) {
            ThoughtsHome()
                .navigationDestination(for: ThoughtsRoute.self) { route in
                    switch route {
                    case .thought(let id, let task, let source):
                        ThoughtDetailView(id: id, focusTask: task)
                            .detailZoom(source, in: zoom)
                    case .tasks:
                        TasksPage()
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
        .environment(checkoff)
    }
}

struct ThoughtsHome: View {
    /// Panel-Kennung „Ohne Thema“ (gleich der Kennung der Karte)
    static let noTopicID = ThoughtMap.noTopicID
    /// Panel-Kennung „Noch nicht geordnet“ (wird geordnet, wartet, Fehler) – nur das Panel, die Karte bleibt
    static let pendingID = "_pending"

    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(CaptureFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var topicAction: TopicAction?
    /// Höhe des Kopfs über der Karte (Überblick, Einrichten, „Offen“)
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        content
            .background(PaplyBackground())
            .navigationTitle("Gedanken")
            // Karte statt Liste: kompakter Kopf wie in Karten/Wo ist?, damit die Karte Platz hat
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SummarySubtitle(text: model.thoughts.isEmpty ? nil : ThoughtsSummary.text(model)))
            .toolbar { toolbar }
            .toolbar { bottomBar }
            .topicActions($topicAction)
            .onChange(of: model.topics.map(\.id)) { _, _ in
                guard let id = nav.focusedTopic, !TopicPalette.isNeutral(id) else { return }
                if let resolved = model.topic(id)?.id {
                    // zusammengeführt (auch automatisch): Panel, Karte und Farbe folgen dem Ziel
                    if resolved != id { nav.focus(resolved) }
                } else {
                    // gewähltes Thema gelöscht → zurück zur Übersicht
                    withAnimation(PaplyMotion.smooth(reduce)) { nav.focus(nil) }
                }
            }
            .onChange(of: nav.focusedTopic) { _, new in
                // VoiceOver: Panel gleich groß, damit alles erreichbar ist
                if new != nil, voiceOver { nav.panelDetent = .large }
            }
            .onChange(of: nav.focusedTopic.map { model.panelThoughts($0).isEmpty } ?? false) { _, empty in
                // alles geordnet bzw. alle Gedanken woandershin verschoben → Panel schließen
                if empty { withAnimation(PaplyMotion.smooth(reduce)) { nav.focus(nil) } }
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
            board
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let bottom = geo.safeAreaInsets.bottom
            let full = geo.size.height + bottom
            let heights = PanelHeights(small: 96 + bottom,
                                       medium: max(min(full * 0.5, full - 200), 96 + bottom + 120),
                                       large: full - 4)
            let panelID = resolvedFocus
            ZStack(alignment: .bottom) {
                // Karte über die volle Höhe (ihr Hintergrund läuft unter dem Kopf durch); ihr Inhalt
                // beginnt unter dem Kopf. Im Thema gehört der Platz der Karte und dem Panel – höchstens
                // bis zur mittleren Stufe: In „groß“ deckt das Panel die Karte ohnehin zu, sie soll dabei
                // nicht auf einen Streifen herauszoomen.
                ThoughtMap(focusedTopic: mapFocus,
                           bottomInset: panelID != nil ? min(heights[nav.panelDetent], heights.medium) : bottom,
                           onOpenThought: { nav.path.append(.thought($0)) })
                    .safeAreaPadding(.top, panelID == nil ? headerHeight : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if panelID == nil {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let panelID {
                    TopicPanel(topicID: panelID, heights: heights, bottomInset: bottom,
                               detent: Bindable(nav).panelDetent,
                               onClose: { withAnimation(PaplyMotion.smooth(reduce)) { nav.focus(nil) } },
                               onAction: { topicAction = $0 })
                        .id(panelID == Self.pendingID ? panelID : "topic")
                        .transition(reduce ? .opacity : .move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(PaplyMotion.smooth(reduce), value: panelID == nil)
        }
    }

    /// Kopf über der Karte: nur was gerade zählt – ggf. die Pille für Ungeordnetes, Einrichten, „Offen“
    private var header: some View {
        let pending = PendingThoughtsPill.count(model)
        return VStack(alignment: .leading, spacing: 10) {
            if pending > 0 {
                PendingThoughtsPill()
                    .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
            }
            if SetupGuide.shared.isVisible(model: model) {
                SetupBanner()
            }
            OpenTasksBar()
        }
        .animation(PaplyMotion.bouncy(reduce), value: pending > 0)
    }

    /// Gewähltes Thema, aufgelöst (ein Alias zeigt sein Ziel) – Karte, Panel und Farbe nutzen dieselbe ID
    private var resolvedFocus: String? {
        guard let id = nav.focusedTopic else { return nil }
        if TopicPalette.isNeutral(id) { return id }
        return model.topic(id)?.id ?? id
    }

    /// Fokus der Karte: Thema bzw. „Ohne Thema“; „Noch nicht geordnet“ lässt die Karte in der Übersicht
    private var mapFocus: Binding<String?> {
        Binding(
            get: { nav.focusedTopic == Self.pendingID ? nil : resolvedFocus },
            set: { new in
                guard new != nav.focusedTopic else { return }
                if new == nil, nav.focusedTopic == Self.pendingID { return }
                nav.focus(new)
            }
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
                Button { nav.path.append(.tasks) } label: {
                    Label("Aufgaben", systemImage: "checklist")
                }
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
    /// im Sperrbildschirm). Als Werkzeugleiste verdeckt er nichts.
    @ToolbarContentBuilder
    private var bottomBar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            // iOS 18: Leiste über der Tab-Leiste mit Anzahl wie in Notizen. iOS 26 setzt den Knopf
            // neben die schwebende Tab-Leiste – dort hätte der Text keinen Platz.
            if !PaplyStyle.usesGlass {
                Text(bottomText)
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

    /// iOS 18: Überblick („320 Gedanken · 8 Themen“), im Thema die Anzahl seiner Gedanken
    private var bottomText: String {
        guard let id = nav.focusedTopic else { return ThoughtsSummary.text(model) }
        let n = model.panelThoughts(id).count
        return n == 1 ? "1 Gedanke" : "\(n) Gedanken"
    }
}

/// iOS 26: Überblick als Untertitel unter „Gedanken“ (iOS 18 zeigt ihn in der unteren Leiste)
private struct SummarySubtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26, *), PaplyStyle.usesGlass, let text {
            content.navigationSubtitle(Text(text).monospacedDigit())
        } else {
            content
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
                                TopicTintBadge(topicID: topic.id, icon: topic.icon, size: 30)
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
                                        .foregroundStyle(TopicPalette.tint(for: topic.id).ink)
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
        nav.focus(topic.id)
        nav.path = []
    }
}
