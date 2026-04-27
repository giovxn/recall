//
//  BreadcrumbManager.swift
//  Recall
//
//  Created by Giovanni Icasiano on 04/04/2026.
//

import Foundation
import CoreLocation
import Combine
import SwiftData

@MainActor
class BreadcrumbManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BreadcrumbManager()
    
    enum TrackingState {
        case idle
        case trackingNormal
        case trackingPoorGPS
    }
    
    enum StopReason {
        case manual
        case timeCap
        case distanceCap
    }
    
    private let manager = CLLocationManager()
    private let confidenceManager = LocationConfidenceManager.shared
    private let navigationStateManager = NavigationStateManager.shared
    private let deadReckoner = MotionDeadReckoner()
    private var activeMemory: MemoryNode?
    private var lastRecordedLocation: CLLocation?
    private var lastRecordedAltitude: Double?
    private var stopTimer: Timer?
    private var modelContext: ModelContext?
    private var totalTrackedDistance: Double = 0
    private var currentSegmentID: UUID = UUID()
    private var poorSignalStartedAt: Date?
    private var pendingReliableSamples: Int = 0
    private var lastDeadReckonedDistance: Double = 0
    private var lastModeRecoveryAt: Date = .distantPast
    private var lastGPSUpdateAt: Date?
    private var consecutiveInvalidGPSSamples: Int = 0
    
    @Published private(set) var activeMemoryID: UUID?
    @Published private(set) var isTracking = false
    @Published private(set) var trackedDistance: Double = 0
    @Published private(set) var lastStopReason: StopReason?
    @Published private(set) var trackingState: TrackingState = .idle
    
    private let maxDuration: TimeInterval = 20 * 60  // 20 minutes
    private let maxTrailDistance: Double = 1_500  // 1.5 km
    private let goodAccuracyThreshold: Double = 15 // clearly good GPS
    private let poorAccuracyThreshold: Double = 28 // clearly poor GPS
    private let maxBreadcrumbAccuracy: Double = 85 // allow outdoors with moderate noise
    private let maxHumanWalkingSpeed: Double = 6.0 // less aggressive speed rejection
    private let maxSingleJumpDistance: Double = 55 // less aggressive jump rejection
    private let minDistanceReliable: Double = 8
    private let minDistanceDegrading: Double = 5
    private let minDistanceUnreliable: Double = 3
    private let minRecoverySamples = 1
    private let invalidSamplesBeforeFallback = 3
    private let segmentBreakAfterPoorSignal: TimeInterval = 24
    private let maxDeadReckoningDuration: TimeInterval = 25
    private let minDeadReckoningStepDistance: Double = 2.5
    private let maxDeadReckoningStepDistance: Double = 8
    private let postRecoverySegmentHold: TimeInterval = 8
    private let minDisplacementForSegmentBreak: Double = 16
    private let gpsStaleIntervalForIndoorFallback: TimeInterval = 6
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = false
    }
    
    func start(for memory: MemoryNode, context: ModelContext) {
        self.activeMemory = memory
        self.modelContext = context
        self.lastRecordedLocation = memory.originalLocation
        self.lastRecordedAltitude = memory.captureAltitude
        self.totalTrackedDistance = 0
        self.currentSegmentID = UUID()
        self.poorSignalStartedAt = nil
        self.pendingReliableSamples = 0
        self.lastDeadReckonedDistance = 0
        self.lastModeRecoveryAt = .distantPast
        self.lastGPSUpdateAt = Date()
        self.consecutiveInvalidGPSSamples = 0
        self.activeMemoryID = memory.id
        self.isTracking = true
        self.trackedDistance = 0
        self.lastStopReason = nil
        self.trackingState = (memory.captureHorizontalAccuracy ?? 0) > poorAccuracyThreshold
            ? .trackingPoorGPS
            : .trackingNormal
        if self.trackingState == .trackingPoorGPS {
            self.poorSignalStartedAt = Date()
        }
        
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        deadReckoner.start()
        deadReckoner.resetAnchor()
        
        // Auto stop after 20 minutes
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.stop(reason: .timeCap)
            }
        }
        
        print("BreadcrumbManager: started for memory \(memory.id)")
    }
    
    func stop(reason: StopReason = .manual) {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        stopTimer?.invalidate()
        stopTimer = nil
        activeMemory = nil
        lastRecordedLocation = nil
        lastRecordedAltitude = nil
        totalTrackedDistance = 0
        currentSegmentID = UUID()
        poorSignalStartedAt = nil
        pendingReliableSamples = 0
        lastDeadReckonedDistance = 0
        lastModeRecoveryAt = .distantPast
        lastGPSUpdateAt = nil
        consecutiveInvalidGPSSamples = 0
        deadReckoner.stop()
        activeMemoryID = nil
        isTracking = false
        trackedDistance = 0
        lastStopReason = reason
        trackingState = .idle
        print("BreadcrumbManager: stopped")
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last,
              let lastLocation = lastRecordedLocation,
              let memory = activeMemory,
              let context = modelContext else { return }
        lastGPSUpdateAt = Date()
        processLocationUpdate(
            newLocation: newLocation,
            lastLocation: lastLocation,
            memory: memory,
            context: context,
            headingFromManager: manager.heading?.trueHeading
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isTracking,
              let anchor = lastRecordedLocation,
              let memory = activeMemory,
              let context = modelContext else { return }
        guard trackingState == .trackingPoorGPS else { return }
        let secondsSinceGPS = Date().timeIntervalSince(lastGPSUpdateAt ?? .distantPast)
        guard secondsSinceGPS >= gpsStaleIntervalForIndoorFallback else { return }
        enterPoorSignalState()
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        maybeRecordDeadReckonedCrumb(
            from: anchor,
            memory: memory,
            context: context,
            fallbackHeading: heading
        )
    }

#if DEBUG
    func ingestSimulatedLocation(_ newLocation: CLLocation, heading: CLLocationDirection? = nil) {
        guard let lastLocation = lastRecordedLocation,
              let memory = activeMemory,
              let context = modelContext else { return }
        processLocationUpdate(
            newLocation: newLocation,
            lastLocation: lastLocation,
            memory: memory,
            context: context,
            headingFromManager: heading
        )
    }

    func ingestSimulatedEstimatedMovement(distanceMeters: Double, heading: CLLocationDirection) {
        guard let anchor = lastRecordedLocation,
              let memory = activeMemory,
              let context = modelContext else { return }
        guard distanceMeters >= minDeadReckoningStepDistance else { return }

        enterPoorSignalState()
        let projectedCoordinate = projectCoordinate(
            from: anchor.coordinate,
            headingDegrees: heading,
            distanceMeters: min(distanceMeters, maxDeadReckoningStepDistance)
        )
        let estimatedLocation = CLLocation(latitude: projectedCoordinate.latitude, longitude: projectedCoordinate.longitude)
        let verticalDelta: Double? = {
            guard let lastRecordedAltitude else { return nil }
            return anchor.altitude - lastRecordedAltitude
        }()
        let crumb = BreadcrumbPoint(
            latitude: projectedCoordinate.latitude,
            longitude: projectedCoordinate.longitude,
            heading: heading,
            stepDistance: min(distanceMeters, maxDeadReckoningStepDistance),
            horizontalAccuracy: nil,
            speed: nil,
            course: nil,
            altitude: anchor.altitude,
            verticalAccuracy: nil,
            verticalDelta: verticalDelta,
            confidenceScore: 0.22,
            segmentID: currentSegmentID,
            isEstimated: true
        )
        appendCrumb(crumb, at: estimatedLocation, distanceMoved: crumb.stepDistance, memory: memory, context: context)
    }
#endif

    private func processLocationUpdate(
        newLocation: CLLocation,
        lastLocation: CLLocation,
        memory: MemoryNode,
        context: ModelContext,
        headingFromManager: CLLocationDirection?
    ) {
        let horizontalAccuracy = newLocation.horizontalAccuracy
        let currentHeading = headingFromManager ?? -1
        confidenceManager.ingest(newLocation)
        navigationStateManager.updateMode(from: confidenceManager.currentConfidence)
        let navigationMode = navigationStateManager.currentMode
        if horizontalAccuracy > 0 {
            if horizontalAccuracy > poorAccuracyThreshold {
                trackingState = .trackingPoorGPS
            } else if horizontalAccuracy <= goodAccuracyThreshold {
                trackingState = .trackingNormal
            } else {
                // Hysteresis neutral band: keep current state without flipping.
            }
        }
        
        let distanceMoved = newLocation.distance(from: lastLocation)
        let speed = newLocation.speed

        let hasAcceptableAccuracy = newLocation.horizontalAccuracy > 0 && newLocation.horizontalAccuracy <= maxBreadcrumbAccuracy
        let hasAcceptableSpeed = speed < 0 || speed <= maxHumanWalkingSpeed
        let hasAcceptableJump = distanceMoved <= maxSingleJumpDistance
        let isValidGPSCrumb = hasAcceptableAccuracy && hasAcceptableSpeed && hasAcceptableJump
        let looksOutdoorReliable =
            newLocation.horizontalAccuracy > 0 &&
            newLocation.horizontalAccuracy <= poorAccuracyThreshold &&
            (speed < 0 || speed <= (maxHumanWalkingSpeed + 0.8)) &&
            distanceMoved <= (maxSingleJumpDistance + 20)
        let shouldAcceptGPSCrumb = isValidGPSCrumb || looksOutdoorReliable

        guard shouldAcceptGPSCrumb else {
            consecutiveInvalidGPSSamples += 1
            guard consecutiveInvalidGPSSamples >= invalidSamplesBeforeFallback else { return }
            enterPoorSignalState()
            maybeRecordDeadReckonedCrumb(
                from: lastLocation,
                memory: memory,
                context: context,
                fallbackHeading: currentHeading
            )
            return
        }
        consecutiveInvalidGPSSamples = 0
        
        let minimumDistanceForMode: Double
        switch navigationMode {
        case .gpsReliable:
            minimumDistanceForMode = minDistanceReliable
        case .gpsDegrading:
            minimumDistanceForMode = minDistanceDegrading
        case .gpsUnreliable:
            minimumDistanceForMode = minDistanceUnreliable
        }
        guard distanceMoved >= minimumDistanceForMode else {
            if trackingState == .trackingPoorGPS {
                pendingReliableSamples = min(minRecoverySamples, pendingReliableSamples + 1)
            }
            return
        }

        if trackingState == .trackingPoorGPS {
            pendingReliableSamples += 1
            if pendingReliableSamples < minRecoverySamples {
                return
            }
            let poorDuration = Date().timeIntervalSince(poorSignalStartedAt ?? .distantPast)
            let cooldownElapsed = Date().timeIntervalSince(lastModeRecoveryAt)
            let shouldBreakForTime = poorDuration >= segmentBreakAfterPoorSignal
            let shouldBreakForDisplacement = distanceMoved >= minDisplacementForSegmentBreak
            if cooldownElapsed >= postRecoverySegmentHold && (shouldBreakForTime || shouldBreakForDisplacement) {
                currentSegmentID = UUID()
            }
            trackingState = .trackingNormal
            poorSignalStartedAt = nil
            pendingReliableSamples = 0
            deadReckoner.resetAnchor()
            lastDeadReckonedDistance = 0
            lastModeRecoveryAt = Date()
            consecutiveInvalidGPSSamples = 0
        }
        
        let heading = currentHeading >= 0 ? currentHeading : 0
        let verticalDelta: Double? = {
            guard let lastRecordedAltitude else { return nil }
            return newLocation.altitude - lastRecordedAltitude
        }()
        
        let confidenceScore = crumbConfidenceScore(
            location: newLocation,
            headingAccuracy: manager.heading?.headingAccuracy,
            speed: speed,
            distanceMoved: distanceMoved,
            previousCrumb: memory.breadcrumbs.last
        )
        let crumb = BreadcrumbPoint(
            latitude: newLocation.coordinate.latitude,
            longitude: newLocation.coordinate.longitude,
            heading: heading,
            stepDistance: distanceMoved,
            horizontalAccuracy: newLocation.horizontalAccuracy > 0 ? newLocation.horizontalAccuracy : nil,
            speed: speed >= 0 ? speed : nil,
            course: newLocation.course >= 0 ? newLocation.course : nil,
            altitude: newLocation.altitude,
            verticalAccuracy: newLocation.verticalAccuracy > 0 ? newLocation.verticalAccuracy : nil,
            verticalDelta: verticalDelta,
            confidenceScore: confidenceScore,
            segmentID: currentSegmentID,
            isEstimated: false
        )
        appendCrumb(crumb, at: newLocation, distanceMoved: distanceMoved, memory: memory, context: context)
        
        if totalTrackedDistance >= maxTrailDistance {
            print("BreadcrumbManager: stopped after distance cap \(Int(totalTrackedDistance))m")
            stop(reason: .distanceCap)
        }
    }

    private func enterPoorSignalState() {
        if trackingState != .trackingPoorGPS {
            trackingState = .trackingPoorGPS
            currentSegmentID = UUID()
            poorSignalStartedAt = Date()
            pendingReliableSamples = 0
            deadReckoner.resetAnchor()
            lastDeadReckonedDistance = 0
        }
    }

    private func maybeRecordDeadReckonedCrumb(
        from anchorLocation: CLLocation,
        memory: MemoryNode,
        context: ModelContext,
        fallbackHeading: CLLocationDirection
    ) {
        guard let poorSignalStartedAt else { return }
        guard Date().timeIntervalSince(poorSignalStartedAt) <= maxDeadReckoningDuration else { return }
        guard deadReckoner.isRunning else { return }

        let estimatedDistance = deadReckoner.distanceSinceAnchor
        let distanceDelta = estimatedDistance - lastDeadReckonedDistance
        guard distanceDelta >= minDeadReckoningStepDistance, distanceDelta <= maxDeadReckoningStepDistance else { return }

        let heading = deadReckoner.headingDegrees ?? (fallbackHeading >= 0 ? fallbackHeading : 0)
        guard deadReckoner.headingStdDev <= 45 else { return }

        let projectedCoordinate = projectCoordinate(
            from: anchorLocation.coordinate,
            headingDegrees: heading,
            distanceMeters: distanceDelta
        )
        let estimatedLocation = CLLocation(latitude: projectedCoordinate.latitude, longitude: projectedCoordinate.longitude)
        let verticalDelta: Double? = {
            guard let lastRecordedAltitude else { return nil }
            return anchorLocation.altitude - lastRecordedAltitude
        }()
        let crumb = BreadcrumbPoint(
            latitude: projectedCoordinate.latitude,
            longitude: projectedCoordinate.longitude,
            heading: heading,
            stepDistance: distanceDelta,
            horizontalAccuracy: nil,
            speed: nil,
            course: nil,
            altitude: anchorLocation.altitude,
            verticalAccuracy: nil,
            verticalDelta: verticalDelta,
            confidenceScore: 0.25,
            segmentID: currentSegmentID,
            isEstimated: true
        )
        appendCrumb(crumb, at: estimatedLocation, distanceMoved: distanceDelta, memory: memory, context: context)
        lastDeadReckonedDistance = estimatedDistance
    }

    private func appendCrumb(
        _ crumb: BreadcrumbPoint,
        at location: CLLocation,
        distanceMoved: Double,
        memory: MemoryNode,
        context: ModelContext
    ) {
        memory.breadcrumbs.append(crumb)
        totalTrackedDistance += max(0, distanceMoved)
        trackedDistance = totalTrackedDistance
        try? context.save()

        lastRecordedLocation = location
        lastRecordedAltitude = location.altitude
        print("Breadcrumb recorded: \(memory.breadcrumbs.count) total")
    }

    private func projectCoordinate(
        from coordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = headingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    private func crumbConfidenceScore(
        location: CLLocation,
        headingAccuracy: CLLocationDirection?,
        speed: CLLocationSpeed,
        distanceMoved: Double,
        previousCrumb: BreadcrumbPoint?
    ) -> Double {
        let accuracy = max(location.horizontalAccuracy, 0)
        let accuracyComponent = 1 - max(0, min(1, (accuracy - 5) / 45))

        let headingAcc = max(0, headingAccuracy ?? 55)
        let headingComponent = 1 - max(0, min(1, headingAcc / 60))

        let speedValue = speed >= 0 ? speed : (previousCrumb?.speed ?? 0)
        let speedComponent = 1 - max(0, min(1, abs(speedValue - 1.4) / 4.5))

        let jumpComponent = 1 - max(0, min(1, distanceMoved / maxSingleJumpDistance))

        let score =
            (accuracyComponent * 0.48) +
            (headingComponent * 0.22) +
            (speedComponent * 0.18) +
            (jumpComponent * 0.12)

        return max(0, min(1, score))
    }
}
