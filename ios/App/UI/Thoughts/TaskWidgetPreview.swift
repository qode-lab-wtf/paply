#if DEBUG
import PaplyKit
import SwiftUI
import UIKit
import WidgetKit

// Nur im Debug: alle Familien des Aufgaben-Widgets in der App gerendert (dieselben Ansichten wie die Erweiterung,
// Shared/UI/TaskWidgetViews.swift), mit Daten aus dem Modell der Oberfläche (z. B. `-PaplyTasksDemo`).
//   -PaplyScreen widgets     Sperrbildschirm entsperrt und gesperrt (Platzhalter), Home klein und mittel
//   -PaplyScreen widgets-2   leere Zustände, „Paply öffnen“, gesperrt in StandBy, kleines Widget auf kleinem iPhone,
//                            derselbe Stand nach Mitternacht
//   -PaplyScreen widgets-3   Beta „Gedanken & Aufgaben“ aus (ruhiger Zustand)
// Größen wie iPhone 14 Pro Max (rund 76, rechteckig 172 × 76, klein 170, mittel 364 × 170, Ränder 16). Der Sperr-
// bildschirm färbt Widgets einfarbig („vibrant“); hier angenähert mit Weiß auf dunklem Hintergrund.
struct TaskWidgetPreview: View {
    let snapshot: TaskSnapshot
    let page: Int
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch page {
                case 2: pageTwo
                case 3: pageThree
                default: pageOne
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: UIColor(hex: 0x0B0F14)).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: Seiten

    @ViewBuilder
    private var pageOne: some View {
        caption("Sperrbildschirm · entsperrt")
        lockScreen(content(snapshot), locked: false)
        caption("Sperrbildschirm · gesperrt (.privacySensitive)")
        lockScreen(content(snapshot), locked: true)
        caption("Home · klein und leer")
        HStack(spacing: 22) {
            home(content(snapshot), family: .systemSmall)
            home(content(.empty(at: now).with(done: 3, now: now)), family: .systemSmall)
        }
        caption("Home · mittel")
        home(content(snapshot), family: .systemMedium)
    }

    @ViewBuilder
    private var pageTwo: some View {
        let empty = TaskSnapshot.empty(at: now)
        caption("Sperrbildschirm · alles erledigt / noch nichts")
        lockScreen(content(empty.with(done: 2, now: now)), locked: false)
        lockScreen(TaskWidgetContent(date: now, state: .noData, requiresAuth: true), locked: false)
        caption("Home · mittel gesperrt (StandBy) und leer")
        home(content(snapshot), family: .systemMedium, locked: true)
        home(content(empty), family: .systemMedium)
        caption("Klein: iPhone 16/15 (158 pt) · nach Mitternacht")
        HStack(spacing: 22) {
            home(content(snapshot), family: .systemSmall, side: 158)
            home(TaskWidgetContent(date: tomorrow, state: .ready(snapshot), requiresAuth: true), family: .systemSmall)
        }
        caption("Klein: noch keine Daten · vor dem ersten Entsperren")
        HStack(spacing: 22) {
            home(TaskWidgetContent(date: now, state: .noData, requiresAuth: true), family: .systemSmall)
            home(TaskWidgetContent(date: now, state: .locked, requiresAuth: true), family: .systemSmall)
        }
    }

    @ViewBuilder
    private var pageThree: some View {
        let off = TaskWidgetContent(date: now, state: .betaOff, requiresAuth: true)
        caption("Beta „Gedanken & Aufgaben“ aus · Sperrbildschirm")
        lockScreen(off, locked: false)
        caption("Beta aus · Home klein und mittel")
        home(off, family: .systemSmall)
        home(off, family: .systemMedium)
    }

    // MARK: Bausteine

    private var tomorrow: Date { TaskSnapshot.startOfNextDay(after: now, calendar: .current).addingTimeInterval(60) }

    private func content(_ snapshot: TaskSnapshot) -> TaskWidgetContent {
        TaskWidgetContent(date: now, state: .ready(snapshot), requiresAuth: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.top, 4)
    }

    /// Reihe unter der Uhr: in der Zeile, rund, rechteckig – auf einem dunklen Hintergrundbild
    private func lockScreen(_ content: TaskWidgetContent, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskWidgetView(content: content, family: .accessoryInline)
                .font(.headline)
                .frame(width: 257, height: 26, alignment: .leading)
            HStack(spacing: 14) {
                TaskWidgetView(content: content, family: .accessoryCircular)
                    .frame(width: 76, height: 76)
                TaskWidgetView(content: content, family: .accessoryRectangular)
                    .frame(width: 172, height: 76)
            }
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .tint(.white)
        .redacted(reason: locked ? .privacy : [])
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(uiColor: UIColor(hex: 0x2B3A55)), Color(uiColor: UIColor(hex: 0x14202E))],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func home(_ content: TaskWidgetContent, family: WidgetFamily, side: CGFloat = 170, locked: Bool = false) -> some View {
        let width: CGFloat = family == .systemMedium ? 364 * side / 170 : side
        return TaskWidgetView(content: content, family: family)
            .padding(16)
            .frame(width: width, height: side)
            .background(TaskWidgetStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .redacted(reason: locked ? .privacy : [])
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    // MARK: Start

    @MainActor
    static func present(model: ThoughtsModel, page: Int) {
        let now = Date()
        let snapshot = TaskWidgetSync.makeSnapshot(model: model, pending: [], now: now)
        let host = UIHostingController(rootView: TaskWidgetPreview(snapshot: snapshot, page: page, now: now))
        host.modalPresentationStyle = .fullScreen
        host.overrideUserInterfaceStyle = .dark
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(host, animated: false)
    }
}

private extension TaskSnapshot {
    /// heute schon `done` erledigt (für die leeren Zustände)
    func with(done: Int, now: Date) -> TaskSnapshot {
        var copy = self
        copy.doneTodayAt = (0..<done).map { now.addingTimeInterval(-Double($0 + 1) * 600) }
        return copy
    }
}
#endif
