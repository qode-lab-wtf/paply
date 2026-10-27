import Darwin
import Foundation
import os

/// CPU-Zeit und Speicher des eigenen Prozesses fürs Diagnoseprotokoll.
enum ProcessMetrics {
    /// Verbrauchte CPU-Zeit (Nutzer + System) in Sekunden seit Prozessstart.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Speicher, den iOS dem Prozess anrechnet (phys_footprint), in MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Wie viel Speicher noch bis zum Jetsam-Limit bleibt (wichtig für die Tastatur), in MB.
    static func availableMB() -> Double {
        Double(os_proc_available_memory()) / 1_048_576
    }

    static var fields: DiagFields {
        [
            "cpuS": .d((cpuSeconds() * 100).rounded() / 100),
            "memMB": .d((footprintMB() * 10).rounded() / 10),
            "memFreeMB": .d((availableMB() * 10).rounded() / 10),
        ]
    }
}
