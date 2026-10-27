import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity eines Gedankens (KONZEPT §3.5). Nie Titel oder Text, höchstens der Themenname.
struct ThoughtLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThoughtActivityAttributes.self) { context in
            Text("Gedanke").foregroundStyle(Color.paplyText)
                .padding(16)
                .activityBackgroundTint(Color.paplyForest.opacity(0.92))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text("Gedanke") }
            } compactLeading: {
                PaplyMark().frame(width: 18, height: 20)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                PaplyMark().frame(width: 16, height: 18)
            }
            .keylineTint(Color.paplyGreenBright)
        }
    }
}
