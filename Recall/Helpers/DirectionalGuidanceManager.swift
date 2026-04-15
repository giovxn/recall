import Foundation
import CoreLocation
import Combine

final class DirectionalGuidanceManager: ObservableObject {
    static let shared = DirectionalGuidanceManager()

    @Published private(set) var directionText: String = "Forward"
    @Published private(set) var relativeDistanceMeters: Double = 0
    @Published private(set) var isActive = false

    private var anchorLocation: CLLocation?

    func activate(anchor: CLLocation) {
        anchorLocation = anchor
        isActive = true
    }

    func deactivate() {
        isActive = false
        relativeDistanceMeters = 0
        directionText = "Forward"
    }

    func update(
        estimatedLocation: CLLocation,
        headingDegrees: Double,
        targetLocation: CLLocation
    ) {
        relativeDistanceMeters = estimatedLocation.distance(from: targetLocation)
        let bearing = DirectionHelper.bearing(from: estimatedLocation, to: targetLocation)
        directionText = directionPrompt(currentHeading: headingDegrees, targetBearing: bearing)
    }

    private func directionPrompt(currentHeading: Double, targetBearing: Double) -> String {
        var delta = targetBearing - currentHeading
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        let absDelta = abs(delta)

        if absDelta <= 12 { return "Forward" }
        if absDelta <= 30 { return delta > 0 ? "Slight right" : "Slight left" }
        if absDelta <= 75 { return delta > 0 ? "Turn right" : "Turn left" }
        return "Turn around"
    }
}
