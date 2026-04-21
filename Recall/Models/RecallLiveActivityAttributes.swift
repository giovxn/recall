import Foundation
import ActivityKit

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
