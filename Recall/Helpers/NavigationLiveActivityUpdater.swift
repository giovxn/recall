import Foundation
import CoreLocation

final class NavigationLiveActivityUpdater: NSObject, CLLocationManagerDelegate {
    static let shared = NavigationLiveActivityUpdater()

    private let manager = CLLocationManager()
    private var targetMemory: MemoryNode?
    private var targetLocation: CLLocation?
    private var fallbackHeading: Double = 0
    private var isRunning = false
    private var lastPushAt: Date = .distantPast
    private var lastDirectionBucket: String?
    private var lastGPSLevel: String?
    private var lastQuantizedRotation: Int?
    private var lastDistanceMeters: Double?
    private let minPushInterval: TimeInterval = 1.5
    private let minDistanceDeltaMeters: Double = 2.0
    private let rotationStepDegrees: Double = 10.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
        manager.distanceFilter = 2
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    func start(memory: MemoryNode) {
        targetMemory = memory
        targetLocation = memory.location
        fallbackHeading = memory.heading
        isRunning = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        targetMemory = nil
        targetLocation = nil
        lastDirectionBucket = nil
        lastGPSLevel = nil
        lastQuantizedRotation = nil
        lastDistanceMeters = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, let current = locations.last else { return }
        pushIfNeeded(currentLocation: current)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isRunning, let current = manager.location else { return }
        pushIfNeeded(currentLocation: current)
    }

    private func pushIfNeeded(currentLocation: CLLocation) {
        guard let targetLocation, let targetMemory else { return }

        let bearing = DirectionHelper.bearing(from: currentLocation, to: targetLocation)
        let heading = resolvedHeading(currentLocation: currentLocation)
        let rotation = normalizedAngle(bearing - heading)
        let quantizedRotation = quantizeRotation(rotation)
        let distanceMeters = DirectionHelper.distance(from: currentLocation, to: targetLocation)
        let distanceText = DirectionHelper.distanceString(from: currentLocation, to: targetLocation)
        let directionText = liveDirectionText(for: Double(quantizedRotation))
        let gpsLevel = gpsLevelText(for: currentLocation.horizontalAccuracy)

        let directionChanged = directionText != lastDirectionBucket
        let gpsChanged = gpsLevel != lastGPSLevel
        let rotationChanged = quantizedRotation != lastQuantizedRotation
        let distanceChanged: Bool = {
            guard let lastDistanceMeters else { return true }
            return abs(distanceMeters - lastDistanceMeters) >= minDistanceDeltaMeters
        }()

        let now = Date()
        let intervalElapsed = now.timeIntervalSince(lastPushAt) >= minPushInterval
        let hasMeaningfulChange = directionChanged || gpsChanged || rotationChanged || distanceChanged
        guard intervalElapsed && hasMeaningfulChange else { return }

        LiveActivityManager.shared.updateActivity(
            distanceText: distanceText,
            directionText: directionText,
            rotationDegrees: Double(quantizedRotation),
            gpsLevel: gpsLevel,
            memoryLabel: targetMemory.smartLabel,
            bgHex: targetMemory.dominantColorHex
        )
        lastPushAt = now
        lastDirectionBucket = directionText
        lastGPSLevel = gpsLevel
        lastQuantizedRotation = quantizedRotation
        lastDistanceMeters = distanceMeters
    }

    private func resolvedHeading(currentLocation: CLLocation) -> Double {
        if let heading = manager.heading {
            if heading.trueHeading >= 0 { return heading.trueHeading }
            if heading.magneticHeading >= 0 { return heading.magneticHeading }
        }
        if currentLocation.course >= 0 { return currentLocation.course }
        return fallbackHeading
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > 180 { normalized -= 360 }
        while normalized < -180 { normalized += 360 }
        return normalized
    }

    private func quantizeRotation(_ angle: Double) -> Int {
        let stepped = (angle / rotationStepDegrees).rounded() * rotationStepDegrees
        return Int(stepped)
    }

    private func liveDirectionText(for angle: Double) -> String {
        let absAngle = abs(angle)
        if absAngle <= 12 { return "Forward" }
        if absAngle <= 30 { return angle > 0 ? "Slight right" : "Slight left" }
        if absAngle <= 75 { return angle > 0 ? "Turn right" : "Turn left" }
        return "Turn around"
    }

    private func gpsLevelText(for horizontalAccuracy: Double) -> String {
        guard horizontalAccuracy > 0 else { return "Low" }
        if horizontalAccuracy <= 12 { return "High" }
        if horizontalAccuracy <= 30 { return "Medium" }
        return "Low"
    }
}
