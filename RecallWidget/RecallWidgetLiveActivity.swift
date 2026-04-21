//
//  RecallWidgetLiveActivity.swift
//  RecallWidget
//
//  Created by Giovanni Icasiano on 21/04/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RecallLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceText: String
        var directionText: String
        var rotationDegrees: Double
        var gpsLevel: String
        var memoryLabel: String
        var bgHex: String
    }

    var memoryID: UUID
    var memoryTimestamp: Date
}

struct RecallWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecallLiveActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.distanceText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(context.state.directionText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("GPS \(context.state.gpsLevel) • \(context.state.memoryLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(context.state.rotationDegrees))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay {
                backgroundColor(hex: context.state.bgHex)
                    .opacity(0.12)
            }
            .activityBackgroundTint(backgroundColor(hex: context.state.bgHex).opacity(0.18))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(context.state.rotationDegrees))
                        .padding(.leading, 12)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText)
                        .font(.system(size: 14, weight: .bold))
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.directionText) • GPS \(context.state.gpsLevel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(context.state.rotationDegrees))
                    .padding(.leading, 4)
            } compactTrailing: {
                Text(context.state.distanceText)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            } minimal: {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(context.state.rotationDegrees))
            }
        }
    }

    private func backgroundColor(hex: String) -> Color {
        Color(hex: hex) ?? .black
    }
}

#Preview("Lock Screen", as: .content, using: RecallLiveActivityAttributes(memoryID: UUID(), memoryTimestamp: .now)) {
    RecallWidgetLiveActivity()
} contentStates: {
    RecallLiveActivityAttributes.ContentState(
        distanceText: "~50m",
        directionText: "Slight left",
        rotationDegrees: -35,
        gpsLevel: "High",
        memoryLabel: "Parking P1-J",
        bgHex: "#0A84FF"
    )
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6, let int = Int(trimmed, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
