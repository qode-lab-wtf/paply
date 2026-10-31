import PaplyKit
import SwiftUI

// Entwicklerbereich → Gedanken (KONZEPT §3.9). Für Nutzer gibt es hier nichts einzustellen.
// Das Tagesbudget liegt unter festen Schlüsseln in UserDefaults (ThoughtsEnvironment liest
// sie); Verbrauch und Themenpflege kommen aus dem ThoughtsModel.

enum ThoughtsDevKeys {
    /// Tokens je gleitende 24 h (Standard 80 000)
    static let dailyTokens = "paply.thoughts.dailyTokens"
}

struct ThoughtsDeveloperSection: View {
    @Environment(ThoughtsModel.self) private var model
    @AppStorage(ThoughtsDevKeys.dailyTokens) private var dailyTokens = 80_000

    var body: some View {
        let queue = model.thoughts.filter { $0.state != .done }.count
        let provisional = model.topics.filter { !model.isActive($0) }.count
        Section {
            Stepper(value: $dailyTokens, in: 20_000...150_000, step: 10_000) {
                LabeledContent("Tagesbudget", value: "\(dailyTokens.formatted(.number.locale(Locale(identifier: "de_DE")))) Tokens")
            }
            LabeledContent("Verbrauch 24 h", value: usageText)
            NavigationLink(value: Route.thoughtQueue) {
                LabeledContent("Warteschlange", value: "\(queue)")
            }
            NavigationLink(value: Route.provisionalTopics) {
                LabeledContent("Vorläufige Themen", value: "\(provisional)")
            }
            Button {
                model.checkTopicsNow()
            } label: {
                HStack {
                    Text("Themenpflege jetzt prüfen")
                    Spacer()
                    if model.isCheckingTopics {
                        ProgressView()
                    } else if let result = model.topicCheckResult {
                        Text(result).foregroundStyle(Color.paplySecondaryText)
                    }
                }
            }
            .disabled(model.isCheckingTopics)
        } header: {
            Text("Gedanken")
        } footer: {
            Text("Die Warteschlange zeigt nur Kennungen und Zustände, nie Text. Themenpflege: ein Aufruf an gpt-oss-20b.")
        }
        .listRowBackground(Color.paplyRow)
        .onAppear { model.refreshUsage() }
    }

    /// „23 400 Tokens · 12 Audio-Min.“
    private var usageText: String {
        guard let usage = model.usage else { return "–" }
        let de = Locale(identifier: "de_DE")
        let tokens = usage.tokens.formatted(.number.locale(de))
        let minutes = Int((Double(usage.audioSeconds) / 60).rounded())
        return "\(tokens) Tokens · \(minutes) Audio-Min."
    }
}

/// Gedanken, die noch nicht fertig sind: Kennung, Zustand, Versuche – nie Text
struct ThoughtQueueView: View {
    @Environment(ThoughtsModel.self) private var model

    var body: some View {
        let queue = model.thoughts.filter { $0.state != .done }
        List {
            if queue.isEmpty {
                Text("Leer – alles geordnet.")
                    .foregroundStyle(Color.paplySecondaryText)
                    .listRowBackground(Color.paplyRow)
            }
            ForEach(queue) { thought in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(String(thought.id.prefix(10)))
                            .font(.body.monospaced())
                        Spacer()
                        Text(thought.state.rawValue)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(Color.paplyBeak)
                    }
                    HStack(spacing: 10) {
                        Text("Versuche \(thought.status.attempts)")
                        if let retry = thought.status.retryAt {
                            Text("ab \(Format.time.string(from: retry))")
                        }
                        Text(Format.dayTime.string(from: thought.createdAt))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.paplySecondaryText)
                }
                .listRowBackground(Color.paplyRow)
            }
        }
        .paplyList()
        .navigationTitle("Warteschlange")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Vorläufige Themen (1 Gedanke, nicht vom Nutzer)
struct ProvisionalTopicsView: View {
    @Environment(ThoughtsModel.self) private var model

    var body: some View {
        let topics = model.topics.filter { !model.isActive($0) }
        List {
            if topics.isEmpty {
                Text("Keine vorläufigen Themen.")
                    .foregroundStyle(Color.paplySecondaryText)
                    .listRowBackground(Color.paplyRow)
            }
            ForEach(topics) { topic in
                HStack(spacing: 12) {
                    TopicBadge(icon: topic.icon, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title)
                        Text("\(String(topic.id.prefix(10))) · \(model.count(of: topic.id)) Gedanke")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.paplySecondaryText)
                    }
                }
                .listRowBackground(Color.paplyRow)
            }
        }
        .paplyList()
        .navigationTitle("Vorläufige Themen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
