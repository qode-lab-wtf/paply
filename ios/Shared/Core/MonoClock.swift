import Darwin
import Foundation

/// Monotone Uhr in Nanosekunden, systemweit gleich (App, Tastatur und Widgets
/// lesen dieselbe Zeitbasis). CLOCK_MONOTONIC_RAW läuft auch im Ruhezustand weiter
/// und wird nicht von NTP verstellt.
enum MonoClock {
    static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }

    static func ms(from start: UInt64, to end: UInt64) -> Double {
        end >= start ? Double(end - start) / 1_000_000 : -Double(start - end) / 1_000_000
    }

    static func msSince(_ start: UInt64) -> Double {
        ms(from: start, to: now())
    }

    /// Prozessstart auf derselben Zeitbasis (aus der Kernel-Startzeit des Prozesses).
    static let processStart: UInt64 = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let monoNow = now()
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return monoNow }
        let start = info.kp_proc.p_un.__p_starttime
        var wall = timeval()
        gettimeofday(&wall, nil)
        let elapsedUs = (Int64(wall.tv_sec) - Int64(start.tv_sec)) * 1_000_000
            + Int64(wall.tv_usec) - Int64(start.tv_usec)
        let elapsedNs = UInt64(max(0, elapsedUs)) * 1_000
        return monoNow > elapsedNs ? monoNow - elapsedNs : 0
    }()
}
