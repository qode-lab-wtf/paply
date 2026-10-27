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

/// Zwei gleichrangige Bereiche (KONZEPT §2): „Gedanken“ (Start) und „Diktat“. Einstellungen als
/// Blatt hinter dem Zahnrad. Über allem: Aufnahme-Leiste, große Aufnahme-Ansicht, FlashView.
struct RootView: View {
    @State private var model: ThoughtsModel
    @State private var nav = ThoughtsNav()
    @State private var flow: CaptureFlow
    @Namespace private var zoom
    private let session = SessionController.shared

    init() {
        PaplyNavigationBar.apply()
        let model = ThoughtsLaunch.makeModel()
        _model = State(initialValue: model)
        _flow = State(initialValue: CaptureFlow(driver: ThoughtsLaunch.makeDriver(model: model)))
    }

    var body: some View {
        @Bindable var nav = nav
        @Bindable var flow = flow
        TabView(selection: $nav.tab) {
            Tab("Gedanken", systemImage: "text.bubble", value: RootTab.thoughts) {
                ThoughtsTab()
            }
            Tab("Diktat", systemImage: "globe", value: RootTab.dictation) {
                DictationTab()
            }
        }
        .modifier(CaptureAccessoryModifier(flow: flow))
        .background { CaptureTracker(flow: flow) }
        .fullScreenCover(isPresented: $flow.showBig) {
            CaptureView()
                .navigationTransition(.zoom(sourceID: flow.zoomSource, in: zoom))
        }
        .sheet(isPresented: $nav.showSettings) {
            SettingsSheet()
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
        .environment(\.captureZoom, zoom)
        .onOpenURL(perform: open)
        .preferredColorScheme(.dark)
        #if DEBUG
        .task { await ThoughtsDebug.apply(nav: nav, flow: flow, model: model) }
        #endif
    }

    /// Deep Links (§2): `thought/current?id=…` (Live Activity), `thought/new` (Rückfall des Sperrbildschirm-
    /// Widgets: Aufnahme in der App), `thought/<id>`, `thoughts/tasks`.
    /// Sitzungs-Links (`session/…`) bearbeitet weiterhin SessionController.handleURL.
    private func open(_ url: URL) {
        guard url.scheme == PaplyURL.scheme else { return }
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
            nav.tab = .thoughts
            if path == "tasks" {
                nav.path = []
                nav.filter = .tasks
            }
        default:
            break
        }
    }
}

/// Einstellungen als Blatt mit eigenem Navigationsstapel
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView()
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
