import ActivityKit
import WidgetKit
import SwiftUI

struct RecallLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var arrow: String
        var distance: String
    }
    
    var memoryTimestamp: Date
}

struct RecallWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecallLiveActivityAttributes.self) { context in
            
            // Lock screen / StandBy UI
            HStack(spacing: 20) {
                Text(context.state.arrow)
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECALL")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .kerning(2)
                    Text(context.state.distance)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("tap to navigate back")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "location.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 24))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.black)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.arrow)
                        .font(.system(size: 32))
                        .padding(.leading, 12)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distance)
                        .font(.system(size: 14, weight: .bold))
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("head back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            } compactLeading: {
                Text(context.state.arrow)
                    .padding(.leading, 4)
            } compactTrailing: {
                Text(context.state.distance)
                    .font(.caption)
                    .padding(.trailing, 4)
            } minimal: {
                Text(context.state.arrow)
            }
        }
    }
}

#Preview("Lock Screen", as: .content, using: RecallLiveActivityAttributes(memoryTimestamp: .now)) {
    RecallWidgetLiveActivity()
} contentStates: {
    RecallLiveActivityAttributes.ContentState(arrow: "↑", distance: "~50m")
}
