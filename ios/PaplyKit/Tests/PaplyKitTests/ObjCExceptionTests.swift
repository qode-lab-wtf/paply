import Foundation
import Testing
@testable import PaplyKit

@Suite("Objective-C-Ausnahmen abfangen")
struct ObjCExceptionTests {
    @Test func catchesARaisedException() {
        let caught = ObjCException.catching {
            NSException(name: .invalidArgumentException, reason: "Tap-Format passt nicht", userInfo: nil).raise()
        }
        #expect(caught?.name == .invalidArgumentException)
        #expect(caught?.reason == "Tap-Format passt nicht")
    }

    @Test func returnsNilWithoutException() {
        var ran = false
        #expect(ObjCException.catching { ran = true } == nil)
        #expect(ran)
    }
}
