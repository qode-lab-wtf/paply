#if DEBUG
import PaplyKit
import SwiftUI
import UIKit

// Nur im Debug: die Karte allein (`-PaplyScreen map`), für Bildschirmfotos ohne Antippen.
//   -PaplyMapFocus        nach dem Start das größte Thema öffnen (mit Panel-Attrappe unten)
//   -PaplyMapFocusID <id> stattdessen diese Kennung öffnen (`_none`, `_more`, Themen-ID)
//   -PaplyMapPanel <0…1>  Höhe der Panel-Attrappe als Anteil (Vorgabe 0,42; 1 = Raststufe „groß“)
//   -PaplyLight           helles Erscheinungsbild (sonst dunkel wie die App)
//   -PaplyMapGrow         nach 2 s: ein gelöschter Gedanke kehrt zurück (Einblenden), ein anderer wechselt das Thema
//   -PaplyMapCrowd        2 000 Gedanken: 500 einzelne vorläufige KI-Themen, 1 500 ohne Thema (Sammelkreis);
//                         mit -PaplyPreviewData starten, damit die Anker nur im Speicher liegen
// Mit -PaplyCount <n> (1, 5, 300 …), -PaplyPreviewData (60), -PaplyMany (2 000) oder -PaplyEmpty kombinieren.
struct MapDebugScreen: View {
    @State var model: ThoughtsModel
    @State private var focus: String?
    @State private var opened: String?

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.bottom
            let panel = focus == nil ? 0 : (Self.panelShare >= 1 ? full - 4 : full * Self.panelShare)
            ZStack(alignment: .bottom) {
                ThoughtMapView(focusedTopic: $focus, bottomInset: panel) { id in
                    opened = model.thought(id)?.displayTitle
                }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                if let focus {
                    DebugPanel(topicID: focus)
                        .frame(height: panel)
                        .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(ThoughtMapView.cameraSpring, value: focus)
        }
        .overlay(alignment: .bottom) {
            if let opened {
                Text("Öffnet: \(opened)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .paplyGlass(.bar)
                    .padding(.bottom, 40)
                    .task(id: opened) {
                        try? await Task.sleep(for: .seconds(1.6))
                        self.opened = nil
                    }
            }
        }
        .environment(model)
        .task {
            if Self.args.contains("-PaplyMapGrow") {
                try? await Task.sleep(for: .seconds(2))
                if let gone = model.deleted.first { model.restore(gone.id) }
                let topics = model.topics.filter { model.count(of: $0.id) > 0 }
                if topics.count >= 2, let mover = model.thoughts.first(where: { $0.topicId == topics[0].id && $0.state == .done }) {
                    model.setTopic(mover.id, topicID: topics[1].id)
                }
            }
            if let id = Self.value(after: "-PaplyMapFocusID") {
                try? await Task.sleep(for: .seconds(1))
                focus = id
                return
            }
            guard Self.args.contains("-PaplyMapFocus") else { return }
            try? await Task.sleep(for: .seconds(1))
            focus = model.topics.max { model.count(of: $0.id) < model.count(of: $1.id) }?.id
        }
    }

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static var panelShare: CGFloat {
        value(after: "-PaplyMapPanel").flatMap(Double.init).map { CGFloat($0) } ?? 0.42
    }

    private var header: some View {
        let topics = Set(model.thoughts.filter { !$0.isProcessing }.map { model.topic($0.topicId)?.id ?? "" }).count
        return VStack(alignment: .leading, spacing: 2) {
            Text("Gedanken")
                .font(.paplyTitle(.largeTitle))
            Text("\(model.thoughts.count) Gedanken · \(topics) \(topics == 1 ? "Thema" : "Themen")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// Attrappe des Panels (baut der Integrator): Kopf mit Thema, darunter die Titel
    private struct DebugPanel: View {
        let topicID: String
        @Environment(ThoughtsModel.self) private var model

        var body: some View {
            let topic = model.topic(topicID)
            let thoughts = topicID == ThoughtMapView.moreID ? model.mapCollectedThoughts()
                : model.thoughts.filter { (model.topic($0.topicId)?.id ?? ThoughtMapView.noTopicID) == topicID && !$0.isProcessing }
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    TopicTintBadge(topicID: topicID, icon: topic?.icon, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(topic?.title ?? (topicID == ThoughtMapView.moreID ? "Weitere Themen" : "Ohne Thema")).font(.title3.weight(.bold))
                        Text("\(thoughts.count) \(thoughts.count == 1 ? "Gedanke" : "Gedanken")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ForEach(thoughts.prefix(4)) { thought in
                    Text(thought.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.07)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paplyGlass(.bar, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        }
    }

    // MARK: Start

    @MainActor
    static func present(model original: ThoughtsModel) {
        let model = args.contains("-PaplyMapCrowd") ? crowd(from: original) : original
        // Farben für genau dieses Modell (Debug-Daten haben ein eigenes Register im Speicher)
        TopicPalette.register(model.topics)
        let host = UIHostingController(rootView: MapDebugScreen(model: model))
        host.modalPresentationStyle = .fullScreen
        host.overrideUserInterfaceStyle = args.contains("-PaplyLight") ? .light : .dark
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(host, animated: false)
    }

    /// 2 000 Gedanken: 500 einzelne vorläufige KI-Themen (je ein Gedanke), 1 500 ohne Thema
    @MainActor
    private static func crowd(from base: ThoughtsModel) -> ThoughtsModel {
        let samples = base.thoughts.filter { $0.state == .done && !$0.textIsRaw }
        guard !samples.isEmpty else { return base }
        let words = ["Garten", "Steuer", "Laufen", "Kochen", "Lesen", "Reise", "Auto", "Musik", "Fotos", "Schule", "Arzt",
                     "Bank", "Geschenke", "Umzug", "Wohnung", "Freunde", "Sport", "Kunst", "Code", "Ideen"]
        let icons = TopicIcon.allCases
        let now = Date()
        var topics: [Topic] = []
        var thoughts: [Thought] = []
        for i in 0..<2_000 {
            var t = samples[i % samples.count]
            t.id = ThoughtIDs.thought()
            t.createdAt = now.addingTimeInterval(-Double(i) * 9_000 - 600)
            t.tasks = t.tasks.map { var k = $0; k.id = ThoughtIDs.task(); return k }
            t.links = []
            if i % 4 == 0 {
                let n = i / 4
                let topic = Topic(title: "\(words[n % words.count]) \(n / words.count + 1)", icon: icons[n % icons.count], owner: .ai,
                                  createdAt: t.createdAt)
                topics.append(topic)
                t.topicId = topic.id
            } else {
                t.topicId = nil
            }
            thoughts.append(t)
        }
        return ThoughtsModel(thoughts: thoughts, topics: topics)
    }
}
#endif
