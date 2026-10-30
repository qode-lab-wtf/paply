import ObjectiveC
import UIKit

/// Öffnet die eigene Container-App aus der Tastatur.
/// `UIApplication.shared` und `open(_:options:completionHandler:)` sind in Erweiterungen
/// gesperrt; `openURL:` geht seit iOS 18 nicht mehr. Apple DTS nennt den Weg über die
/// Responder-Kette bis zur UIApplication für die eigene App als zulässig. Auf iOS 26 nur mit
/// Vollzugriff (sonst Fehler -54). Protokolliert wird, welcher Weg greift.
///
/// 1. Standard: `openURL:options:completionHandler:` auf der UIApplication aus der Responder-Kette
///    (Signatur passt genau zur öffentlichen Methode).
/// 2. Rückfall: `extensionContext.open` (für Tastaturen offiziell nicht vorgesehen, harmlos).
/// 3. Rückfall: altes `openURL:` (seit iOS 18 wirkungslos, nur fürs Protokoll).
@MainActor
enum AppOpener {
    typealias Completion = @MainActor @Sendable (_ variant: String, _ success: Bool) -> Void

    /// C-Signatur von -[UIApplication openURL:options:completionHandler:]
    private typealias OpenURLWithOptions = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) @Sendable (Bool) -> Void)?) -> Void

    static func open(_ url: URL, from controller: UIInputViewController, completion: @escaping Completion) {
        let started = MonoClock.now()
        let application = findApplication(from: controller)
        Diag.log("kb.open.begin", ["appInChain": .b(application != nil)])
        openViaApplication(application, url: url, started: started) { success in
            if success { return completion("responder", true) }
            guard let context = controller.extensionContext else {
                return legacy(url, responder: controller, started: started, completion: completion)
            }
            // Rückruf kommt auf einer fremden Queue: @Sendable, dann zurück auf den Main-Actor
            context.open(url) { @Sendable success in
                Task { @MainActor in
                    Diag.log("kb.open.variant", ["variant": .s("extensionContext"), "ok": .b(success), "ms": .ms(MonoClock.msSince(started))])
                    if success { completion("extensionContext", true) } else { legacy(url, responder: controller, started: started, completion: completion) }
                }
            }
        }
    }

    private static func openViaApplication(_ application: UIApplication?, url: URL, started: UInt64, next: @escaping @MainActor @Sendable (Bool) -> Void) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        guard let application, application.responds(to: selector),
              let method = class_getInstanceMethod(type(of: application), selector)
        else {
            Diag.log("kb.open.variant", ["variant": .s("responder"), "available": .b(false)])
            return next(false)
        }
        let function = unsafeBitCast(method_getImplementation(method), to: OpenURLWithOptions.self)
        // Rückruf kommt auf einer fremden Queue: nicht MainActor-isoliert, erst danach hinüber
        let handler: @convention(block) @Sendable (Bool) -> Void = { success in
            Task { @MainActor in
                Diag.log("kb.open.variant", ["variant": .s("responder"), "ok": .b(success), "ms": .ms(MonoClock.msSince(started))])
                next(success)
            }
        }
        function(application, selector, url as NSURL, NSDictionary(), handler)
    }

    /// Rückfall 3: altes `openURL:` – seit iOS 18 wirkungslos, nur zum Protokollieren.
    private static func legacy(_ url: URL, responder: UIResponder, started: UInt64, completion: Completion) {
        let selector = NSSelectorFromString("openURL:")
        var current: UIResponder? = responder
        while let r = current {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                Diag.log("kb.open.variant", ["variant": .s("openURL:"), "class": .s(String(describing: type(of: r))), "ms": .ms(MonoClock.msSince(started))])
                return completion("openURL:", false) // kein Rückmeldewert – gilt nicht als Erfolg
            }
            current = r.next
        }
        Diag.log("kb.open.failed", ["ms": .ms(MonoClock.msSince(started))])
        completion("none", false)
    }

    private static func findApplication(from responder: UIResponder) -> UIApplication? {
        var current: UIResponder? = responder
        while let r = current {
            if let application = r as? UIApplication { return application }
            current = r.next
        }
        return nil
    }
}

/// EXPERIMENTELL (Schalter in der App, Standard aus): liest die Bundle-ID der Host-App über
/// private Felder und protokolliert sie NUR. Kein Rücksprung – private Wege verstoßen gegen
/// Guideline 2.5.1 und sind ab iOS 26.4 gesperrt.
/// Im Release-Build NICHT einkompiliert (private Felder; App-Store-Prüfung).
@MainActor
enum HostProbe {
    static func log(from controller: UIInputViewController) {
        #if DEBUG
        guard SharedSettings.logHostBundleID else { return }
        var fields: DiagFields = ["parentClass": .s(controller.parent.map { String(describing: type(of: $0)) } ?? "–")]
        let objects: [(String, AnyObject?)] = [("self", controller), ("parent", controller.parent)]
        for (label, object) in objects {
            for name in ["_hostBundleID", "_hostApplicationBundleIdentifier"] {
                fields["\(label).\(name)"] = ivarString(object, name).map { .s($0) } ?? .null
            }
        }
        Diag.log("kb.host.experimental", fields)
        #endif
    }

    #if DEBUG
    private static func ivarString(_ object: AnyObject?, _ name: String) -> String? {
        guard let object, let ivar = class_getInstanceVariable(type(of: object), name),
              let encoding = ivar_getTypeEncoding(ivar), String(cString: encoding).hasPrefix("@")
        else { return nil }
        return object_getIvar(object, ivar) as? String
    }
    #endif
}
