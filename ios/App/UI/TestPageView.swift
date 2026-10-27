import Observation
import SwiftUI
import UIKit

/// Misst per keyboardWillChangeFrame die Höhe jeder Tastatur. Apples Höhe und die Leiste,
/// die iOS unter Drittanbieter-Tastaturen zeichnet, landen in der App Group; die Paply-Tastatur
/// nutzt sie beim nächsten Erscheinen. Alle Messungen gehen ins Protokoll.
@MainActor
@Observable
final class HeightLab {
    enum Kind: String {
        case apple, paply, emoji, other, unknown

        var label: String {
            switch self {
            case .apple: "Apple"
            case .paply: "Paply"
            case .emoji: "Emoji"
            case .other: "Andere"
            case .unknown: "?"
            }
        }
    }

    struct Measurement: Identifiable {
        let id = UUID()
        let kind: Kind
        let height: Double
        let landscape: Bool
        let mode: String
        let at: Date
    }

    private(set) var log: [Measurement] = []
    private(set) var heights = SharedSettings.keyboardHeights
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var firstFrameNs: UInt64?
    /// Für die Auswertung wird die aktive Tastatur frisch gelesen (nicht die beim Frame-Wechsel).
    @ObservationIgnored weak var textView: UITextView?

    /// Jeder Frame wird roh protokolliert (auch das Start-Flackern), ausgewertet wird
    /// erst, wenn die Höhe 0,8 s stillsteht.
    func frameChanged(height: Double, landscape: Bool, mode: UITextInputMode?, duration: Double) {
        let now = MonoClock.now()
        if firstFrameNs == nil { firstFrameNs = now }
        let info = Self.describe(mode)
        Diag.log("height.frame", [
            "h": .d(height), "landscape": .b(landscape), "mode": .s(info.id), "lang": .s(info.lang),
            "animS": .d(duration), "sinceFirstMs": .ms(MonoClock.ms(from: firstFrameNs ?? now, to: now)),
        ])
        settleTask?.cancel()
        guard height > 0 else { return }
        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            evaluate(height: height, landscape: landscape, retry: true)
        }
    }

    private func evaluate(height: Double, landscape: Bool, retry: Bool) {
        let info = Self.describe(textView?.textInputMode)
        let report = SharedStore.read(KeyboardReport.self, .keyboardReport)
        let reportFresh = report.map { MonoClock.ms(from: $0.ns, to: MonoClock.now()) < 5_000 && $0.landscape == landscape } ?? false
        var kind = Self.classify(info)
        if (kind == .unknown || kind == .paply), !reportFresh, retry {
            // Die Tastatur meldet ihre Höhe erst kurz nach dem Erscheinen – nochmal versuchen
            settleTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                evaluate(height: height, landscape: landscape, retry: false)
            }
            return
        }
        if kind == .unknown, reportFresh { kind = .paply }

        switch kind {
        case .apple:
            if landscape { heights.appleLandscape = height } else { heights.applePortrait = height }
        case .paply:
            if let report, reportFresh {
                if landscape {
                    heights.paplyFrameLandscape = height
                    heights.paplyViewLandscape = report.viewHeight
                } else {
                    heights.paplyFramePortrait = height
                    heights.paplyViewPortrait = report.viewHeight
                }
            }
        default:
            break
        }
        heights.measuredAt = Date()
        SharedSettings.keyboardHeights = heights
        log.insert(Measurement(kind: kind, height: height, landscape: landscape, mode: info.id, at: Date()), at: 0)
        if log.count > 30 { log.removeLast() }
        Diag.log("height.measure", [
            "kind": .s(kind.rawValue),
            "h": .d(height),
            "landscape": .b(landscape),
            "mode": .s(info.id),
            "paplyView": reportFresh ? .d(report?.viewHeight ?? 0) : .null,
            "target": .opt(heights.targetViewHeight(landscape: landscape)),
        ])
    }

    func reset() {
        heights = KeyboardHeights()
        SharedSettings.keyboardHeights = heights
        log.removeAll()
        Diag.log("height.reset")
    }

    /// EXPERIMENTELL (nur Testseite): `identifier` ist eine private Eigenschaft von
    /// UITextInputMode; sie wird nur gelesen, wenn das Objekt darauf antwortet.
    private static func describe(_ mode: UITextInputMode?) -> (id: String, lang: String) {
        guard let mode else { return ("–", "–") }
        var id = "?"
        #if DEBUG // nicht öffentlich – im Release nicht einkompiliert
        if mode.responds(to: NSSelectorFromString("identifier")), let value = mode.value(forKey: "identifier") as? String {
            id = value
        }
        #endif
        return (id, mode.primaryLanguage ?? "–")
    }

    private static func classify(_ info: (id: String, lang: String)) -> Kind {
        if !AppGroup.keyboardBundleID.isEmpty, info.id.contains(AppGroup.keyboardBundleID) { return .paply }
        if info.lang == "emoji" || info.id.hasPrefix("emoji") { return .emoji }
        if info.lang == "mul" { return .paply } // PrimaryLanguage der Paply-Tastatur
        if info.id == "?" || info.id == "–" { return info.lang == "–" ? .unknown : .apple }
        // Apple: „de_DE@sw=QWERTZ-German;hw=…“, Drittanbieter: Bundle-ID
        let head = info.id.split(separator: "@").first.map(String.init) ?? info.id
        return head.contains(".") ? .other : .apple
    }
}

struct TestPageView: View {
    @State private var lab = HeightLab()

    var body: some View {
        List {
            Section {
                MeasuringTextView(lab: lab)
                    .frame(minHeight: 110)
            } header: {
                Text("Textfeld")
            } footer: {
                Text("1. Hier tippen (Apple-Tastatur). 2. Mit 🌐 zu Paply wechseln. 3. Das Gleiche im Querformat. Danach hat Paply genau Apples Höhe. Hier kannst du auch ein Diktat ausprobieren.")
            }

            Section("Gemessen") {
                row("Apple hochkant", heights.applePortrait)
                row("Paply hochkant (gesamt)", heights.paplyFramePortrait)
                row("Paply-Fläche hochkant", heights.paplyViewPortrait)
                row("→ Zielhöhe hochkant", heights.targetViewHeight(landscape: false))
                row("Apple quer", heights.appleLandscape)
                row("→ Zielhöhe quer", heights.targetViewHeight(landscape: true))
                if let fallback = KeyboardHeightTable.defaultViewHeight(
                    screenWidth: Double(UIScreen.main.bounds.width),
                    screenHeight: Double(UIScreen.main.bounds.height),
                    landscape: false
                ) {
                    row("Standardtabelle hochkant", fallback)
                }
                Button("Messwerte zurücksetzen", role: .destructive) { lab.reset() }
            }

            if !lab.log.isEmpty {
                Section("Verlauf der Messungen") {
                    ForEach(lab.log) { m in
                        HStack {
                            Text(m.kind.label).fontWeight(.semibold)
                            Text(m.landscape ? "quer" : "hochkant").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(m.height)) pt").monospacedDigit()
                        }
                    }
                }
            }
        }
        .paplyList()
        .navigationTitle("Testseite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heights: KeyboardHeights { lab.heights }

    private func row(_ title: String, _ value: Double?) -> some View {
        LabeledContent(title, value: value.map { "\(Int($0.rounded())) pt" } ?? "–")
    }
}

/// UITextView ohne Zubehörleiste (sonst stimmt die gemessene Höhe nicht).
private struct MeasuringTextView: UIViewRepresentable {
    let lab: HeightLab

    func makeCoordinator() -> Coordinator { Coordinator(lab: lab) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.textColor = Brand.text
        view.inputAccessoryView = nil
        view.isScrollEnabled = true
        context.coordinator.textView = view
        lab.textView = view
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let lab: HeightLab
        weak var textView: UITextView?
        private var observer: NSObjectProtocol?

        init(lab: HeightLab) {
            self.lab = lab
            super.init()
            observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
                MainActor.assumeIsolated {
                    self?.handle(end: end, duration: duration)
                }
            }
        }

        private func handle(end: CGRect, duration: Double) {
            guard let textView, let window = textView.window else { return }
            let visible = end.intersection(window.bounds).height
            let landscape = window.bounds.width > window.bounds.height
            lab.frameChanged(height: Double(visible), landscape: landscape, mode: textView.textInputMode, duration: duration)
        }
    }
}
