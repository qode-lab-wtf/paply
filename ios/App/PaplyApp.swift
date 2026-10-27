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
            // Sprachen aus Tastaturen + Gerätesprachen nur im Vordergrund ableiten und merken
            if phase == .active { AppSettings.shared.refreshDetectedSpokenLanguages() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let keys = (launchOptions ?? [:]).keys.map(\.rawValue).sorted().joined(separator: ",")
        Diag.log("app.launch", [
            "app": .s(SessionController.appState),
            "options": .s(keys),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: MonoClock.now())),
            "version": .s(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"),
            "os": .s(UIDevice.current.systemVersion),
            "appGroup": .b(AppGroup.containerURL != nil),
        ])
        SessionController.shared.bootstrap()
        return true
    }
}
