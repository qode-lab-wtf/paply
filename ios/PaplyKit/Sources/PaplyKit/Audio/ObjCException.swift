import Foundation
import PaplyObjC

/// Objective-C-Ausnahmen abfangen (Swift kann `@try/@catch` nicht selbst).
public enum ObjCException {
    /// Führt `body` aus; liefert die Ausnahme, falls eine geworfen wurde, sonst nil.
    public static func catching(_ body: () -> Void) -> NSException? {
        PaplyCatchException(body)
    }
}
