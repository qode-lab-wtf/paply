import PaplyKit
import SwiftUI

// Kopf der Startseite über der Karte (Entwurf „Landkarte“): ggf. eine Pille für noch nicht geordnete
// Gedanken, ggf. das kompakte Einrichten-Band und die Leiste „Offen“ mit der nächsten Aufgabe – direkt
// abhakbar, „Alle n“ führt zur Aufgabenliste. Der Überblick („320 Gedanken · 8 Themen“) steht nicht mehr als
// eigene Zeile über der Karte, sondern als Untertitel (iOS 26) bzw. in der unteren Leiste (iOS 18).

/// „40 Gedanken · 8 Themen“
enum ThoughtsSummary {
    @MainActor
    static func text(_ model: ThoughtsModel) -> String {
        let thoughts = model.thoughts.count
        let topics = model.topics.reduce(0) { $0 + (model.count(of: $1.id) > 0 ? 1 : 0) }
        let t = thoughts == 1 ? "1 Gedanke" : "\(thoughts) Gedanken"
        guard topics > 0 else { return t }
        return t + " · " + (topics == 1 ? "1 Thema" : "\(topics) Themen")
    }
}

/// Pille für Gedanken, die Paply noch ordnet oder die warten – öffnet das Panel „Noch nicht geordnet“.
/// Erscheint nur, wenn es solche Gedanken gibt (`count`).
struct PendingThoughtsPill: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Anzahl der Gedanken, die noch geordnet werden oder warten
    @MainActor
    static func count(_ model: ThoughtsModel) -> Int {
        model.thoughts.reduce(0) { $0 + ($1.isProcessing || $1.isWaiting ? 1 : 0) }
    }

    var body: some View {
        let thoughts = model.thoughts
        let processing = thoughts.reduce(0) { $0 + ($1.isProcessing ? 1 : 0) }
        let waiting = thoughts.reduce(0) { $0 + ($1.isWaiting ? 1 : 0) }
        let attention = thoughts.contains { $0.state == .needsAttention }
        Button {
            withAnimation(PaplyMotion.smooth(reduce)) { nav.focus(ThoughtsHome.pendingID) }
        } label: {
            HStack(spacing: 6) {
                LucideImage(waiting == 0 ? .sparkles : (attention ? .triangleAlert : .hourglass), size: 13, stroke: 2.2,
                            relativeTo: .footnote)
                    .foregroundStyle(attention ? Color.paplyBeak : ThoughtTint.mint)
                Text(text(processing: processing, waiting: waiting))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .shimmer(processing > 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.paplyTertiaryText)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.paplyText)
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .frame(minHeight: 30)
            .paplyGlass(.plain, interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityHint("Zeigt die Gedanken, die Paply noch ordnet")
    }

    private func text(processing: Int, waiting: Int) -> String {
        if waiting == 0 { return processing == 1 ? "Wird geordnet" : "\(processing) werden geordnet" }
        if processing == 0 { return waiting == 1 ? "1 wartet" : "\(waiting) warten" }
        return "\(processing + waiting) noch ungeordnet"
    }
}

// MARK: - Leiste „Offen“

/// Die nächste offene Aufgabe (fällige zuerst). Abhaken: Kreis füllt sich, nach 1,2 s gleitet die
/// nächste herein. Text antippen öffnet den Gedanken an der Aufgabe.
struct OpenTasksBar: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let open = model.openTasks(topicID: nil)
        Group {
            if let next = open.first {
                row(next, total: open.count)
                    .id(next.task.id)
                    .transition(reduce ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            } else if !model.doneTasks(days: 7).isEmpty {
                done
                    .transition(.opacity)
            }
        }
        .animation(PaplyMotion.smooth(reduce), value: open.first?.task.id)
    }

    private func row(_ item: (task: ThoughtTask, thought: Thought), total: Int) -> some View {
        let done = checkoff.isShownDone(item.task)
        let topic = model.topic(item.thought.topicId)
        let overdue = !done && (item.task.dueAt.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false)
        let big = typeSize.isAccessibilitySize
        return HStack(alignment: big ? .top : .center, spacing: 12) {
            TaskCheckButton(task: item.task, thoughtID: item.thought.id, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(done ? Color.paplySecondaryText : Color.paplyText)
                    .strikethrough(done, color: Color.paplySecondaryText)
                    .lineLimit(big ? 4 : 1)
                meta(item, topic: topic, overdue: overdue, big: big)
                if big, total > 1 { allButton(total).padding(.top, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { nav.path.append(.thought(item.thought.id, task: item.task.id)) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Öffnet den Gedanken")
            if total > 1, !big {
                allButton(total)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(ThoughtCardSurface(cornerRadius: 18))
    }

    /// „Als Nächstes · morgen · ◆ Paply“ – bei großer Schrift umbrechend statt gekürzt
    @ViewBuilder
    private func meta(_ item: (task: ThoughtTask, thought: Thought), topic: Topic?, overdue: Bool, big: Bool) -> some View {
        let hint = item.task.dueHint.flatMap { $0.isEmpty ? nil : $0 }
        if big {
            metaText(hint: hint, topic: topic, overdue: overdue)
                .font(.footnote)
                .foregroundStyle(Color.paplySecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 4) {
                Text("Als Nächstes")
                if let hint {
                    Text("·")
                    Text(hint)
                        .fontWeight(overdue ? .semibold : .regular)
                        .foregroundStyle(overdue ? Color.paplyBeak : Color.paplySecondaryText)
                }
                if let topic {
                    Text("·")
                    TopicGlyph(key: topic.icon.rawValue, size: 12, stroke: 2, relativeTo: .footnote)
                        .foregroundStyle(TopicPalette.tint(for: topic.id).ink)
                    Text(topic.title)
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.paplySecondaryText)
            .lineLimit(1)
        }
    }

    private func metaText(hint: String?, topic: Topic?, overdue: Bool) -> Text {
        var text = Text("Als Nächstes")
        if let hint {
            text = text + Text(" · ") + Text(hint).foregroundStyle(overdue ? Color.paplyBeak : Color.paplySecondaryText)
        }
        if let topic { text = text + Text(" · \(topic.title)") }
        return text
    }

    private func allButton(_ total: Int) -> some View {
        Button {
            nav.path.append(.tasks)
        } label: {
            Text("Alle \(total)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.paplyGreenBright)
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .accessibilityLabel("Alle \(total) offenen Aufgaben")
    }

    private var done: some View {
        HStack(spacing: 10) {
            LucideImage(.check, size: 16, stroke: 2.8, relativeTo: .subheadline)
                .foregroundStyle(Color.paplyGreenBright)
            Text("Alles erledigt")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.paplySecondaryText)
            Spacer(minLength: 6)
            Button {
                nav.path.append(.tasks)
            } label: {
                Text("Erledigte")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.paplyGreenBright)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(ThoughtCardSurface(cornerRadius: 18))
    }
}

// MARK: - Einrichten (kompakt)

/// Über der Karte ist kein Platz für die große Einrichtungskarte: ein Band mit Fortschritt, das sie als
/// Blatt öffnet. Sind alle Schritte erledigt, verschwindet es (wie die Karte).
struct SetupBanner: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @State private var open = false
    private let guide = SetupGuide.shared

    var body: some View {
        let done = guide.doneCount(model: model)
        let total = SetupGuide.Step.allCases.count
        Button {
            open = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                        .stroke(Color.paplyGreenBright, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Einrichten")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                    Text("\(done) von \(total) erledigt")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.paplySecondaryText)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.paplyTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ThoughtCardSurface(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Einrichten, \(done) von \(total) erledigt")
        .onAppear { guide.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { guide.refresh() }
        }
        .onChange(of: nav.showSettings) { _, show in
            // „Eintragen“ (Groq-Schlüssel) öffnet die Einstellungen – erst dieses Blatt schließen
            guard show, open else { return }
            nav.showSettings = false
            open = false
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                nav.showSettings = true
            }
        }
        .sheet(isPresented: $open) {
            NavigationStack {
                ScrollView {
                    SetupCard()
                        .padding(16)
                }
                .background(PaplyBackground())
                .navigationTitle("Einrichten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { open = false }.fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
            .tint(.paplyGreenBright)
        }
    }
}
