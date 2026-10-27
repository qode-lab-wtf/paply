import PaplyKit
import SwiftUI

// Bausteine der Aufgaben (KONZEPT §3.3): Abhaken überall gleich (TaskCheckoff) – Kreis füllt sich sofort, nach
// 1,2 s gleitet die Aufgabe aus den offenen Listen. Erneutes Tippen in der Zeit macht es rückgängig – auch im
// Detail. Die Sammelsicht ist der Reiter „Aufgaben“ (TasksTab.swift).

/// Abgehakt, aber noch nicht übernommen – geteilt von Reiter „Aufgaben“, Karten, Panel und Detail (eine Instanz für
/// die ganze App, `RootView`), damit dieselbe Aufgabe überall gleich aussieht und sich überall gleich verhält.
@MainActor
@Observable
final class TaskCheckoff {
    private(set) var pending: Set<String> = []
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]

    func isShownDone(_ task: ThoughtTask) -> Bool { task.done || pending.contains(task.id) }

    func toggle(_ task: ThoughtTask, thoughtID: String, model: ThoughtsModel, reduceMotion: Bool) {
        let key = task.id
        let smooth = PaplyMotion.smooth(reduceMotion)
        // immer der aktuelle Stand, nicht der einer evtl. veralteten Ansicht
        guard let current = Self.task(key, in: thoughtID, model: model) else {
            forget(key, animation: smooth)
            return
        }
        if let running = timers[key] {
            // in der Wartezeit erneut getippt: rückgängig. Wurde sie inzwischen woanders erledigt, wieder
            // öffnen – ein Tippen dreht immer den sichtbaren Zustand um.
            running.cancel()
            timers[key] = nil
            withAnimation(smooth) {
                _ = pending.remove(key)
                if current.done { model.toggleTask(thoughtID, key) }
            }
            return
        }
        if current.done {
            withAnimation(smooth) { model.toggleTask(thoughtID, key) }
            return
        }
        withAnimation(smooth) { _ = pending.insert(key) }
        timers[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            self.timers[key] = nil
            // neu lesen: nur umschalten, wenn die Aufgabe noch da und noch offen ist
            let still = Self.task(key, in: thoughtID, model: model)
            withAnimation(smooth) {
                if let still, !still.done { model.toggleTask(thoughtID, key) }
                _ = self.pending.remove(key)
            }
        }
    }

    /// Sofort erledigt (Wischen nach rechts) bzw. sofort wieder offen – ohne Wartezeit; eine laufende endet.
    func set(_ task: ThoughtTask, done: Bool, thoughtID: String, model: ThoughtsModel, reduceMotion: Bool) {
        let key = task.id
        let smooth = PaplyMotion.smooth(reduceMotion)
        timers.removeValue(forKey: key)?.cancel()
        withAnimation(smooth) {
            _ = pending.remove(key)
            if let current = Self.task(key, in: thoughtID, model: model), current.done != done {
                model.toggleTask(thoughtID, key)
            }
        }
    }

    /// Aufgabe gibt es nicht mehr (gelöscht, Gedanke gelöscht): Wartezeit beenden, nichts schreiben
    private func forget(_ key: String, animation: Animation?) {
        timers.removeValue(forKey: key)?.cancel()
        if pending.contains(key) { withAnimation(animation) { _ = pending.remove(key) } }
    }

    private static func task(_ id: String, in thoughtID: String, model: ThoughtsModel) -> ThoughtTask? {
        guard let thought = model.thought(thoughtID), thought.deletedAt == nil else { return nil }
        return thought.tasks.first { $0.id == id }
    }
}

/// Runder Haken wie im Entwurf: Ring, beim Abhaken grün gefüllt mit Haken (Bouncy)
struct TaskCheckCircle: View {
    let done: Bool
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduce
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let s = size * min(scale, 1.6)
        ZStack {
            Circle()
                .strokeBorder(done ? Color.clear : Color.paplyText.opacity(0.42), lineWidth: 1.6)
                .background(Circle().fill(done ? Color.paplyGreenBright : Color.clear))
            LucideImage(.check, size: s * 0.62, stroke: 3.4, scales: false)
                .foregroundStyle(Color.paplyForest)
                .scaleEffect(done ? 1 : 0.2)
                .opacity(done ? 1 : 0)
        }
        .frame(width: s, height: s)
        .animation(PaplyMotion.bouncy(reduce), value: done)
        .accessibilityHidden(true)
    }
}

/// Haken als Knopf mit großer Trefferfläche (44 pt), Haptik wie in der Liste
struct TaskCheckButton: View {
    let task: ThoughtTask
    let thoughtID: String
    var size: CGFloat = 22

    @Environment(ThoughtsModel.self) private var model
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let done = checkoff.isShownDone(task)
        Button {
            checkoff.toggle(task, thoughtID: thoughtID, model: model, reduceMotion: reduce)
        } label: {
            TaskCheckCircle(done: done, size: size)
                .padding(11)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.86))
        .padding(-11)
        .sensoryFeedback(trigger: done) { _, new in new ? .impact(weight: .light) : .selection }
        .accessibilityLabel(done ? "Erledigt: \(task.text)" : "Abhaken: \(task.text)")
        .accessibilityHint(done ? "Tippen öffnet die Aufgabe wieder" : "")
    }
}

/// Eine Aufgabe im Detail: Kreis · Text · rechts der Zeitpunkt (Wortlaut am Tag der Aufnahme, danach der Tag –
/// wie im Reiter Aufgaben)
struct TaskLine: View {
    let task: ThoughtTask
    /// Aufnahme des Gedankens (ab dann gilt der Wortlaut „morgen“ usw.)
    let recordedAt: Date
    /// sichtbar erledigt, aber noch nicht übernommen (1,2 s)
    var pendingDone = false
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce

    private var shownDone: Bool { task.done || pendingDone }
    private var overdue: Bool { !shownDone && (task.dueAt.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false) }
    private var due: String? { TaskDueLabel.make(task: task, recordedAt: recordedAt).map { TaskDueText.text($0) } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: shownDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(shownDone ? Color.paplyGreenBright : Color.paplyText.opacity(0.5))
                    .symbolEffect(.bounce, value: shownDone)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shownDone ? "Erledigt" : "Offen")
            .accessibilityHint(shownDone ? "Tippen öffnet die Aufgabe wieder" : "Tippen hakt die Aufgabe ab")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .font(.body)
                    .foregroundStyle(shownDone ? Color.paplySecondaryText : Color.paplyText)
                    .strikethrough(shownDone, color: Color.paplySecondaryText)
                    .animation(PaplyMotion.smooth(reduce), value: shownDone)
            }
            Spacer(minLength: 8)
            if let due {
                Text(due)
                    .font(.subheadline)
                    .foregroundStyle(overdue ? Color.paplyBeak : Color.paplySecondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        // Haptik (§4): abhaken leicht, wieder öffnen Auswahl
        .sensoryFeedback(trigger: shownDone) { _, new in new ? .impact(weight: .light) : .selection }
        .accessibilityElement(children: .combine)
    }
}
