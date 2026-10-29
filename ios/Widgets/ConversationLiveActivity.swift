import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let conversationBlue = Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
private let conversationTeal = Color(red: 63 / 255, green: 208 / 255, blue: 201 / 255)

struct ConversationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConversationActivityAttributes.self) { context in
            VStack(spacing: 14) {
                HStack {
                    ConversationMark().frame(width: 36, height: 36)
                    VStack(alignment: .leading) {
                        Text("Gespräch").font(.headline)
                        Text(context.state.caption).font(.subheadline)
                    }
                    Spacer()
                    ConversationTime(state: context.state)
                }
                ConversationFinish(id: context.attributes.conversationID, state: context.state)
            }
            .padding(16)
            .activityBackgroundTint(Color.paplyForest)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(Self.url(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ConversationMark().frame(width: 32, height: 32) }
                DynamicIslandExpandedRegion(.trailing) { ConversationTime(state: context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        Text(context.state.caption)
                        ConversationFinish(id: context.attributes.conversationID, state: context.state)
                    }
                }
            } compactLeading: {
                ConversationMark().frame(width: 20, height: 20)
            } compactTrailing: {
                ConversationTime(state: context.state).frame(maxWidth: 48)
            } minimal: {
                ConversationMark().frame(width: 20, height: 20)
            }
            .keylineTint(conversationBlue)
            .widgetURL(Self.url(context.attributes.conversationID))
        }
    }
    static func url(_ id: String) -> URL? { URL(string: "paply-ios://conversation/\(id)") }
}
private struct ConversationMark: View {
    var body: some View {
        PaplyMark().padding(5).background {
            Circle().stroke(LinearGradient(colors: [conversationBlue, conversationTeal], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
        }
    }
}
private struct ConversationTime: View {
    let state: ConversationActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.phase == .recording {
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
            } else if state.phase == .paused {
                Image(systemName: "pause.fill")
            } else {
                Image(systemName: state.phase == .done ? "checkmark" : "ellipsis")
            }
        }.monospacedDigit().foregroundStyle(conversationBlue)
    }
}
private struct ConversationFinish: View {
    let id: String
    let state: ConversationActivityAttributes.ContentState
    var body: some View {
        if state.phase == .recording || state.phase == .paused {
            Button(intent: FinishConversationIntent(id: id)) {
                Label("Fertig", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).tint(conversationBlue).foregroundStyle(.black)
        }
    }
}
