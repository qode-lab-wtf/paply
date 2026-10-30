import SwiftUI
import UIKit

@main
struct PaplyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { SessionController.shared.handleURL($0) }
                .tint(.paplyGreenBright)
        }
        .onChange(of: scenePhase) { _, phase in
            Diag.log("app.scene", ["phase": .s("\(phase)"), "status": .s(SessionController.shared.status.rawValue)])
            if phase != .active, case .running = SessionController.shared.flash {
                SessionController.shared.flash = nil
            }
            if phase == .active {
                SessionController.shared.lastActivatedAt = Date()
                SetupStatus.shared.refresh()
                // Sprachen aus Tastaturen + Gerätesprachen nur im Vordergrund ableiten und merken
                AppSettings.shared.refreshDetectedSpokenLanguages()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == ConversationModels.sessionID else { completionHandler(); return }
        ConversationModels.shared.completion = completionHandler
        ConversationModels.shared.start()
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let keys = (launchOptions ?? [:]).keys.map(\.rawValue).sorted().joined(separator: ",")
        Diag.log("app.launch", [
            "app": .s(SessionController.appState),
            "options": .s(keys),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: MonoClock.now())),
            "version": .s(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"),
            "os": .s(UIDevice.current.systemVersion),
            "appGroup": .s(AppGroup.identifier),
            "container": .opt(AppGroup.containerURL?.path),
            "base": .opt(AppGroup.baseURL?.path),
        ])
        // Vor dem ersten Entsperren nach einem Neustart (Gedanken-Knopf, BGTask) ist nichts lesbar:
        // Laden und Aufräumen warten dann auf `protectedDataDidBecomeAvailable` (ProtectedData).
        ProtectedData.startObserving()
        SessionController.shared.bootstrap()
        ThoughtBridge.bootstrap()
        // Gedanken: Speicher, Warteschlange, BGTask „com.paply.ios.thoughts“ (muss vor Ende des Starts registriert sein)
        ThoughtsEnvironment.bootstrap()
        ConversationsEnvironment.bootstrap()
        // Aufgaben-Widgets: Momentaufnahme schreiben, im Widget Abgehaktes anwenden
        TaskWidgetSync.bootstrap()
        // Erinnerung zur Uhrzeit: Delegate muss vor Ende des Starts stehen (Aktionen „Erledigt“, „In 1 Stunde“).
        // Fragt nie nach der Erlaubnis.
        TaskReminders.shared.start()
        return true
    }
}

/// Dateien, UserDefaults und Schlüsselbund der App haben die Schutzklasse „bis zur ersten Anmeldung“.
/// Startet iOS die App nach einem Neustart vor dem ersten Entsperren (Gedanken-Knopf Fall B, BGTask),
/// liest alles leer – wer dann schreibt, überschreibt die echten Daten. Deshalb: Laden aufschieben,
/// bis die Daten lesbar sind, und bis dahin nichts speichern.
@MainActor
enum ProtectedData {
    private static var readable = false
    private static var waiting: [(Bool) -> Void] = []
    private static var observers: [NSObjectProtocol] = []

    /// true, sobald seit dem Neustart einmal entsperrt wurde (bleibt bis zum nächsten Neustart so).
    /// `isProtectedDataAvailable` ist auch bei gesperrtem Gerät false, obwohl die Daten dann lesbar
    /// sind – deshalb entscheidet im gesperrten Zustand ein Schreibtest mit derselben Schutzklasse.
    static var isReadable: Bool {
        if !readable, UIApplication.shared.isProtectedDataAvailable || probe() { readable = true }
        return readable
    }

    /// Sofort ausführen, wenn lesbar (`deferred` = false); sonst nach dem ersten Entsperren (`deferred` = true).
    static func whenReadable(_ work: @escaping @MainActor (_ deferred: Bool) -> Void) {
        if isReadable {
            work(false)
            return
        }
        if waiting.isEmpty { Diag.log("app.protectedData.waiting") }
        waiting.append(work)
    }

    /// Erneut prüfen (Entsperren, Vordergrund, Gedanken-Druck, BGTask) und Aufgeschobenes ausführen.
    static func check() {
        guard !waiting.isEmpty, isReadable else { return }
        let work = waiting
        waiting = []
        Diag.log("app.protectedData.available", ["deferred": .i(work.count), "app": .s(SessionController.appState)])
        for item in work { item(true) }
    }

    /// Aus `didFinishLaunching`. Ein ausgesetzter Prozess bekommt das Entsperren evtl. nicht mit –
    /// daher auch Vordergrund und Aktivierung.
    static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names = [
            UIApplication.protectedDataDidBecomeAvailableNotification,
            UIApplication.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { check() }
            })
        }
    }

    /// Neue Datei mit der Schutzklasse der App anlegen – scheitert genau vor dem ersten Entsperren.
    private static func probe() -> Bool {
        let dir = ThoughtsEnvironment.root
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let probe = dir.appendingPathComponent(".probe")
        do {
            try Data([1]).write(to: probe, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
