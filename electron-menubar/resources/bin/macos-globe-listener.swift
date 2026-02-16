import Cocoa
import Carbon

// Globe/Fn key listener using CGEventTap.
// Unlike NSEvent.addGlobalMonitorForEvents (passive), CGEventTap can
// INTERCEPT and SUPPRESS events — preventing the emoji picker from opening.
// Outputs "FN_DOWN" / "FN_UP" on stdout so the Electron app can read it.
// Requires Accessibility permissions on macOS.

setbuf(stdout, nil)

var fnIsDown = false
var tapRef: CFMachPort?

let callback: CGEventTapCallBack = { proxy, type, event, refcon in

    // Re-enable tap if system disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = tapRef {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .flagsChanged else {
        return Unmanaged.passRetained(event)
    }

    let flags = event.flags
    let fnPressed = flags.contains(.maskSecondaryFn)

    // Check if other modifiers are also held (Shift, Ctrl, Alt, Cmd)
    let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
    let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty

    if fnPressed && !hasOtherModifiers {
        // Standalone Fn press — suppress emoji picker
        if !fnIsDown {
            fnIsDown = true
            print("FN_DOWN")
        }
        return nil
    } else if !fnPressed && fnIsDown {
        // Fn released
        fnIsDown = false
        print("FN_UP")
        return nil
    }

    // Fn + other modifier combo (e.g. Fn+Backspace) — cancel our tracking, let it through
    if fnPressed && hasOtherModifiers && fnIsDown {
        fnIsDown = false
        print("FN_UP")
    }

    return Unmanaged.passRetained(event)
}

// Create event tap
let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    fputs("ERROR: Could not create event tap. Grant Accessibility permissions in System Settings → Privacy & Security → Accessibility.\n", stderr)
    exit(1)
}

tapRef = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

CFRunLoopRun()
