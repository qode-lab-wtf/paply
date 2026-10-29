import PaplyKit
import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case vocabulary
    case spokenLanguages
    case thoughtButton
    case keyboardSetup
    case developer
    case testVariants
    case testPage
    case diagnostics
    case storageCheck
    case thoughtQueue
    case provisionalTopics
    case entry(String)
}

/// Vier Reiter: Gedanken | Gespräche | Aufgaben | Diktat. Einstellungen als
/// Blatt hinter dem Zahnrad. Über allem: Aufnahme-Leiste, große Aufnahme-Ansicht, FlashView.
/// Beta „Gedanken & Aufgaben“ aus (`AppSettings.betaThoughts`): keine Reiter, das Diktat ist die Startseite.
struct RootView: View {
    @State private var model: ThoughtsModel
    @State private var nav = ThoughtsNav()
    @State private var flow: CaptureFlow
    /// Abhaken mit Wartezeit – eine für alle Reiter, damit dieselbe Aufgabe überall gleich aussieht
    @State private var checkoff = TaskCheckoff()
    @Namespace private var zoom
    @Environment(\.scenePhase) private var scenePhase
    private let session = SessionController.shared
    private let settings = AppSettings.shared

    init() {
        PaplyNavigationBar.apply()
        let model = ThoughtsLaunch.makeModel()
        _model = State(initialValue: model)
        _flow = State(initialValue: CaptureFlow(driver: ThoughtsLaunch.makeDriver(model: model)))
    }

    var body: some View {
        @Bindable var nav = nav
        @Bindable var flow = flow
        content
        .modifier(ConversationCapturePresentation())
        .animation(.paplySmooth, value: settings.betaThoughts)
        .background { CaptureTracker(flow: flow) }
        .fullScreenCover(isPresented: $flow.showBig) {
            CaptureView()
                .navigationTransition(.zoom(sourceID: flow.zoomSource, in: zoom))
        }
        .sheet(isPresented: $nav.showSettings, onDismiss: { nav.settingsFocus = nil }) {
            SettingsSheet(focus: nav.settingsFocus)
        }
        // Themenwahl aus dem Detail – in beiden Reitern (Gedanken, Aufgaben)
        .sheet(item: $nav.topicPicker) { item in
            TopicPickerSheet(thoughtID: item.id)
        }
        .overlay {
            if let flash = session.flash {
                FlashView(flash: flash) {
                    withAnimation(.paplySmooth) { session.flash = nil }
                } openSettings: {
                    session.flash = nil
                    nav.showSettings = true
                }
                .transition(.opacity)
            }
        }
        .animation(.paplySmooth, value: session.flash)
        .environment(model)
        .environment(nav)
        .environment(flow)
        .environment(checkoff)
        .environment(\.captureZoom, zoom)
        .onOpenURL(perform: open)
        .onChange(of: ConversationNavigation.shared.requestedID, initial: true) { _, id in
            if id != nil, settings.betaConversations { nav.tab = .conversations }
        }
        .task { TopicImages.shared.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { TaskDay.shared.refresh() }
        }
        .onChange(of: settings.betaConversations) { _, on in
            if !on, nav.tab == .conversations { nav.tab = .dictation }
        }
        .onChange(of: settings.betaThoughts) { _, on in
            // Aus: Reiter weg, das Diktat bleibt (sanft eingeblendet). Wieder an: man steht im Reiter Diktat, die
            // Gedanken sind mit allem wieder da.
            if !on { nav.tab = .dictation }
        }
        .betaHintAlert {
            nav.settingsFocus = SettingsView.betaAnchor
            nav.showSettings = true
        }
        .onChange(of: nav.toast) { old, new in
            // Hinweis abgelaufen oder ersetzt: Widerrufen ist vorbei (auch per Schütteln)
            guard let token = old?.undo, token != new?.undo else { return }
            model.forgetUndo(token)
            ThoughtsUndo.forget(token)
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .task { await ThoughtsDebug.apply(nav: nav, flow: flow, model: model) }
        #endif
    }

    /// Mit Beta: vier Reiter. Ohne: nur das Diktat (wie die Startseite vor den Gedanken).
    @ViewBuilder
    private var content: some View {
        @Bindable var nav = nav
        if settings.betaThoughts || settings.betaConversations {
            TabView(selection: $nav.tab) {
                if settings.betaThoughts {
                    Tab("Gedanken", systemImage: "text.bubble", value: RootTab.thoughts) {
                        ThoughtsTab()
                    }
                }
                if settings.betaConversations {
                    Tab("Gespräche", systemImage: "person.2.wave.2", value: RootTab.conversations) {
                        ConversationsTab()
                    }
                }
                if settings.betaThoughts {
                    Tab("Aufgaben", systemImage: "checklist", value: RootTab.tasks) {
                        TasksTab()
                    }
                    .badge(TasksBadge.count(model))
                }
                Tab("Diktat", systemImage: "globe", value: RootTab.dictation) {
                    DictationTab()
                }
            }
            .modifier(CaptureAccessoryModifier(flow: flow))
            .transition(.opacity)
        } else {
            DictationTab()
                .transition(.opacity)
        }
    }

    /// Deep Links (§2): `thought/current?id=…` (Live Activity), `thought/new` (Rückfall des Sperrbildschirm-
    /// Widgets: Aufnahme in der App), `thought/<id>`, `thoughts/tasks` (Reiter Aufgaben),
    /// `task/<Gedanke>/<Aufgabe>` (Aufgaben-Widget: Detail an der Aufgabe), `beta/thoughts` (Gedanken-Knopf bei
    /// ausgeschalteter Beta). Ist die Beta „Gedanken & Aufgaben“ aus, zeigen alle diese Links nur den Hinweis.
    /// Sitzungs-Links (`session/…`) bearbeitet weiterhin SessionController.handleURL.
    private func open(_ url: URL) {
        if url.isFileURL {
            Task { await ConversationCapture.shared.importAudio(url) }
            return
        }
        if url.scheme == PaplyURL.scheme, url.host == "conversation" {
            let id = url.lastPathComponent
            ConversationNavigation.shared.showCurrent = id == "current" && ConversationCapture.shared.active != nil
            ConversationNavigation.shared.requestedID = id == "current" ? ConversationCapture.shared.active?.id : id
            if SessionController.shared.status == .interrupted {
                SessionController.shared.attemptResume(trigger: "conversation-link", attempt: 1)
            }
            return
        }
        guard url.scheme == PaplyURL.scheme else { return }
        let host = url.host ?? ""
        guard settings.betaThoughts else {
            if ["thought", "thoughts", "task", "beta"].contains(host) {
                Diag.log("thoughts.link.betaOff", ["host": .s(host)])
                BetaHint.shared.show()
            }
            return
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch url.host {
        case "thought":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
            if path == "new" {
                // große Ansicht; ohne laufende Aufnahme startet sie eine, sonst zeigt sie die laufende
                nav.tab = .thoughts
                if flow.driver.active == nil || !flow.showBig { flow.openBig(source: CaptureFlow.fabSource) }
            } else if path == "current" || path.isEmpty {
                if flow.driver.active != nil {
                    nav.tab = .thoughts
                    if !flow.showBig { flow.openBig(source: CaptureFlow.barSource) }
                } else if let id, !id.isEmpty {
                    nav.open(id)
                }
            } else {
                nav.open(path)
            }
        case "thoughts":
            if path == "tasks" {
                nav.showTasks()
            } else {
                nav.tab = .thoughts
            }
        case "task":
            // Aufgaben-Widget: `task/<Gedanke>/<Aufgabe>` → Reiter Aufgaben, Gedanke an der Aufgabe
            // (nach einem Kaltstart sind die Gedanken evtl. noch nicht gelesen – dann trotzdem öffnen; gelöscht → nur Reiter)
            let parts = path.split(separator: "/").map(String.init)
            nav.showTasks()
            if parts.count == 2, !model.isLoaded || model.thought(parts[0]) != nil {
                nav.tasksPath = [.thought(parts[0], task: parts[1])]
            }
        default:
            break
        }
    }
}

/// Einstellungen als Blatt mit eigenem Navigationsstapel. `focus`: Abschnitt, zu dem es beim Öffnen rollt.
private struct SettingsSheet: View {
    var focus: String?
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(focus: focus)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .settings: SettingsView()
                    case .vocabulary: VocabularyView()
                    case .spokenLanguages: SpokenLanguagesView()
                    case .thoughtButton: ThoughtButtonGuideView()
                    case .keyboardSetup: KeyboardSetupView()
                    case .developer: DeveloperView()
                    case .testVariants: TestVariantsView()
                    case .testPage: TestPageView()
                    case .diagnostics: DiagnosticsView()
                    case .storageCheck: StorageCheckView()
                    case .thoughtQueue: ThoughtQueueView()
                    case .provisionalTopics: ProvisionalTopicsView()
                    case .entry(let id): HistoryDetailView(id: id, showToast: { _ in })
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(.paplyGreenBright)
    }
}
