import PaplyKit
import SwiftUI
import UIKit

struct ConversationsTab: View {
    @Environment(ThoughtsModel.self) private var thoughts
    @Environment(ThoughtsNav.self) private var nav
    @State private var model = ConversationsModel.shared
    @State private var path: [String] = []
    @State private var voices = false
    @State private var deleted = false
    var body: some View {
        NavigationStack(path: $path) {
            ConversationsHome(
                items: model.conversations.filter { $0.deletedAt == nil }.compactMap {
                    model.display($0.id, thoughts: thoughts)
                },
                showPrivacyHint: AppSettings.shared.conversationRecordingCount < 3,
                onRecord: {
                    Task {
                        model.stopPlayback()
                        if ConversationCapture.shared.active == nil {
                            _ = await ConversationCapture.shared.toggle(trigger: .app)
                        }
                        let running = ConversationCapture.shared.active != nil
                        ConversationNavigation.shared.showCurrent = running
                        if !running {
                            ConversationNavigation.shared.error = ConversationCapture.shared.notice ?? "Die Aufnahme konnte nicht starten."
                        }
                    }
                }, onOpen: { path.append($0) }, onVoices: { voices = true }, onDeleted: { deleted = true },
                onSettings: { nav.showSettings = true }
            )
            .safeAreaInset(edge: .top) {
                if !ConversationModels.shared.ready {
                    Button { ConversationModels.shared.start() } label: {
                        Text(ConversationModels.shared.failed ? "Fehler – erneut versuchen" : "Sprechererkennung wird geladen … \(Int(ConversationModels.shared.fraction * 100)) %")
                            .font(.footnote).padding(8)
                    }
                }
            }
            .task { ConversationModels.shared.start() }
            .navigationDestination(for: String.self) { ConversationDetailHost(id: $0) }
            .navigationDestination(isPresented: $deleted) { RecentlyDeletedView() }
            .sheet(isPresented: $voices) {
                NavigationStack {
                    ConversationKnownVoicesView(
                        people: model.people,
                        onDelete: { id in
                            model.perform { try await ConversationsEnvironment.profiles.delete(id) }
                        })
                }
            }
        }
        .onChange(of: ConversationNavigation.shared.requestedID, initial: true) { _, id in
            guard let id else { return }
            path = [id]
            ConversationNavigation.shared.requestedID = nil
        }
    }
}

struct ConversationDetailHost: View {
    let id: String
    @Environment(ThoughtsModel.self) private var thoughts
    @Environment(ThoughtsNav.self) private var nav
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    @State private var model = ConversationsModel.shared
    @State private var speakerID: String?
    @State private var utteranceID: String?
    @State private var share = false
    var body: some View {
        Group {
            if let item = model.display(id, thoughts: thoughts), item.conversation.deletedAt == nil {
                ConversationDetailView(
                    item: item, utterances: model.transcripts[id] ?? [], playingUtteranceID: model.playingUtteranceID,
                    audioAvailable: model.audioIDs.contains(id), pendingTaskIDs: checkoff.pending,
                    actions: actions(item)
                )
                .sheet(isPresented: Binding(get: { speakerID != nil }, set: { if !$0 { speakerID = nil } })) {
                    if let speaker = item.conversation.speakers.first(where: { $0.id == speakerID }) {
                        ConversationSpeakerSheet(
                            speaker: speaker, speakers: item.conversation.speakers, people: model.people,
                            onChoose: {
                                model.choose($0, speaker: speaker, id: id)
                                speakerID = nil
                            }, onCancel: { speakerID = nil })
                    }
                }
                .sheet(isPresented: Binding(get: { utteranceID != nil }, set: { if !$0 { utteranceID = nil } })) {
                    NavigationStack {
                        ConversationUtteranceSpeakerSheet(
                            speakers: item.conversation.speakers, selectedID: nil,
                            onChoose: { target in
                                if let utteranceID {
                                    model.perform {
                                        try await ConversationsEnvironment.editing.reassignUtterance(
                                            id, utteranceID: utteranceID, to: target)
                                    }
                                }
                                utteranceID = nil
                            }, onCancel: { utteranceID = nil })
                    }
                }
                .sheet(isPresented: $share) { ConversationShare(text: model.shareText(item)) }
            } else {
                ContentUnavailableView("Gespräch nicht verfügbar", systemImage: "text.bubble")
            }
        }
        .task(id: id) {
            await model.reload()
            await model.loadTranscript(id)
        }
        .onDisappear { model.unloadTranscript(id) }
        .alert("Gespräch", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
    private func actions(_ item: ConversationDisplay) -> ConversationDetailActions {
        ConversationDetailActions(
            rename: { title in model.perform { try await ConversationsEnvironment.editing.rename(id, title: title) } },
            chooseTopic: { nav.topicPicker = SheetID(id: id) }, speaker: { speakerID = $0 },
            suggestion: { speakerID, yes in
                guard let speaker = item.conversation.speakers.first(where: { $0.id == speakerID }) else { return }
                if yes, let suggestion = speaker.suggestion {
                    model.choose(.suggestion(suggestion), speaker: speaker, id: id)
                } else {
                    model.perform {
                        try await ConversationsEnvironment.editing.rejectSuggestion(id, speakerID: speakerID)
                    }
                }
            },
            toggleTask: { taskID in
                if let task = item.tasks.first(where: { $0.id == taskID }) {
                    checkoff.toggle(task, thoughtID: id, model: thoughts, reduceMotion: reduce)
                }
            }, play: { model.play(id, utterance: $0, continuing: false) }, reassign: { utteranceID = $0 },
            copyUtterance: { utteranceID in
                UIPasteboard.general.string = model.transcripts[id]?.first { $0.id == utteranceID }?.text
            }, playFrom: { model.play(id, utterance: $0, continuing: true) }, share: { share = true },
            copyTranscript: { model.copyTranscript(item) },
            retry: { model.perform { try await ConversationsEnvironment.processor.retry(id) } },
            delete: {
                _ = thoughts.delete(id)
                dismiss()
            })
    }
}

private struct ConversationShare: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ConversationCapturePresentation: ViewModifier {
    @State private var navigation = ConversationNavigation.shared
    private let capture = ConversationCapture.shared
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if !CaptureBarPlacement.usesAccessory || (!AppSettings.shared.betaThoughts && !AppSettings.shared.betaConversations) {
                    ConversationActiveBar()
                }
            }
            .fullScreenCover(isPresented: $navigation.showCurrent) {
                if let active = capture.active {
                    TimelineView(.periodic(from: .now, by: 1)) { time in
                        ConversationRecordingView(
                            elapsed: capture.elapsed, paused: active.paused,
                            showGuidance: AppSettings.shared.conversationRecordingCount < 3, level: { capture.level },
                            onPause: { capture.setPaused(!active.paused) },
                            onFinish: {
                                capture.finish()
                                navigation.showCurrent = false
                            },
                            onDiscard: {
                                capture.discard()
                                navigation.showCurrent = false
                            }, onMinimize: { navigation.showCurrent = false })
                    }
                }
            }
            .onChange(of: capture.active) { _, active in if active == nil { navigation.showCurrent = false } }
            .alert(
                "Gespräch",
                isPresented: Binding(get: { navigation.error != nil }, set: { if !$0 { navigation.error = nil } })
            ) {
                Button("OK") { navigation.error = nil }
            } message: {
                Text(navigation.error ?? "")
            }
    }
}

struct ConversationActiveBar: View {
    private let capture = ConversationCapture.shared
    var body: some View {
        if let active = capture.active {
            TimelineView(.periodic(from: .now, by: 1)) { time in
                ConversationRecordingBar(
                    elapsed: capture.elapsed, paused: active.paused,
                    level: { capture.level }, onOpen: { ConversationNavigation.shared.showCurrent = true },
                    onPause: { capture.setPaused(!active.paused) }, onFinish: { capture.finish() })
            }
        }
    }
}
