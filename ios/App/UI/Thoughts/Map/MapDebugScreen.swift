#if DEBUG
import PaplyKit
import SwiftUI
import UIKit

// Nur im Debug: die Karte allein (`-PaplyScreen map`), für Bildschirmfotos ohne Antippen.
//   -PaplyMapFocus        nach dem Start das größte Thema öffnen (mit Panel-Attrappe unten)
//   -PaplyLight           helles Erscheinungsbild (sonst dunkel wie die App)
//   -PaplyMapGrow         nach 2 s: ein gelöschter Gedanke kehrt zurück (Einblenden), ein anderer wechselt das Thema
// Mit -PaplyCount <n> (1, 5, 300 …), -PaplyPreviewData (60), -PaplyMany (2 000) oder -PaplyEmpty kombinieren.
struct MapDebugScreen: View {
    @State var model: ThoughtsModel
    @State private var focus: String?
    @State private var opened: String?

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    var body: some View {
        GeometryReader { geo in
            let panel = focus == nil ? 0 : (geo.size.height + geo.safeAreaInsets.bottom) * 0.42
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
            guard Self.args.contains("-PaplyMapFocus") else { return }
            try? await Task.sleep(for: .seconds(1))
            focus = model.topics.max { model.count(of: $0.id) < model.count(of: $1.id) }?.id
        }
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
            let thoughts = model.thoughts.filter { (model.topic($0.topicId)?.id ?? ThoughtMapView.noTopicID) == topicID && !$0.isProcessing }
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    TopicTintBadge(topicID: topicID, icon: topic?.icon, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(topic?.title ?? "Ohne Thema").font(.title3.weight(.bold))
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
    static func present(model: ThoughtsModel) {
        // Farben für genau dieses Modell (im Debug kann ein zweites Modell das Register überschrieben haben)
        TopicPalette.register(model.topics)
        let host = UIHostingController(rootView: MapDebugScreen(model: model))
        host.modalPresentationStyle = .fullScreen
        host.overrideUserInterfaceStyle = args.contains("-PaplyLight") ? .light : .dark
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(host, animated: false)
    }
}
#endif
