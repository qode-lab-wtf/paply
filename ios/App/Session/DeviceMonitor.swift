import Foundation
import UIKit

/// Akku, Thermik, Energiesparmodus, Speicher und CPU-Zeit fürs Diagnoseprotokoll –
/// alle 10 Minuten und bei jeder Änderung, solange eine Sitzung läuft.
@MainActor
final class DeviceMonitor {
    private var observers: [NSObjectProtocol] = []
    private var lastCPU: Double = 0
    private var lastCPUAt = Date()
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        lastCPU = ProcessMetrics.cpuSeconds()
        lastCPUAt = Date()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionController.shared.monitor.logMetrics(reason: "battery") }
            },
            center.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionController.shared.monitor.logMetrics(reason: "batteryState") }
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionController.shared.monitor.logMetrics(reason: "thermal") }
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionController.shared.monitor.logMetrics(reason: "lowPower") }
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionController.shared.monitor.logMetrics(reason: "memoryWarning") }
            },
        ]
        logMetrics(reason: "start")
    }

    func stop() {
        guard running else { return }
        logMetrics(reason: "stop")
        running = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    var batteryPercent: Int? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Int((level * 100).rounded())
    }

    func logMetrics(reason: String) {
        let cpu = ProcessMetrics.cpuSeconds()
        let elapsed = Date().timeIntervalSince(lastCPUAt)
        let cpuPercent = elapsed > 1 ? (cpu - lastCPU) / elapsed * 100 : 0
        lastCPU = cpu
        lastCPUAt = Date()

        var fields: DiagFields = [
            "reason": .s(reason),
            "battery": batteryPercent.map { .i($0) } ?? .null,
            "batteryState": .s(Self.batteryStateName),
            "thermal": .s(Self.thermalName),
            "lowPower": .b(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "cpuPct": .d((cpuPercent * 100).rounded() / 100),
        ]
        fields.merge(ProcessMetrics.fields) { a, _ in a }
        fields.merge(SessionController.shared.metricsFields) { a, _ in a }
        Diag.log("metrics", fields)
    }

    private static var batteryStateName: String {
        switch UIDevice.current.batteryState {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    private static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
