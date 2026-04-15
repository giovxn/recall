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
    private var activeMemory: MemoryNode?
    private var lastRecordedLocation: CLLocation?
    private var lastRecordedAltitude: Double?
    private var stopTimer: Timer?
    private var modelContext: ModelContext?
    private var totalTrackedDistance: Double = 0
    
    @Published private(set) var activeMemoryID: UUID?
    @Published private(set) var isTracking = false
    @Published private(set) var trackedDistance: Double = 0
    @Published private(set) var lastStopReason: StopReason?
    @Published private(set) var trackingState: TrackingState = .idle
    
    private let maxDuration: TimeInterval = 20 * 60  // 20 minutes
    private let maxTrailDistance: Double = 1_500  // 1.5 km
    private let goodAccuracyThreshold: Double = 15 // clearly good GPS
    private let poorAccuracyThreshold: Double = 28 // clearly poor GPS
    private let maxBreadcrumbAccuracy: Double = 65 // drop very noisy crumbs
    private let maxHumanWalkingSpeed: Double = 4.5 // speed sanity
    private let maxSingleJumpDistance: Double = 50 // jump rejection
    private let minDistanceReliable: Double = 10
    private let minDistanceDegrading: Double = 6
    private let minDistanceUnreliable: Double = 4
    
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
        self.activeMemoryID = memory.id
        self.isTracking = true
        self.trackedDistance = 0
        self.lastStopReason = nil
        self.trackingState = (memory.captureHorizontalAccuracy ?? 0) > poorAccuracyThreshold
            ? .trackingPoorGPS
            : .trackingNormal
        
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        
        // Auto stop after 20 minutes
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stop(reason: .timeCap)
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
        
        let horizontalAccuracy = newLocation.horizontalAccuracy
        let currentHeading = manager.heading?.trueHeading ?? -1
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
        
        // Keep heading/GPS recovery logic active, but reject clearly noisy breadcrumb points.
        guard newLocation.horizontalAccuracy > 0,
              newLocation.horizontalAccuracy <= maxBreadcrumbAccuracy else { return }
        guard speed < 0 || speed <= maxHumanWalkingSpeed else { return }
        guard distanceMoved <= maxSingleJumpDistance else { return }
        
        let minimumDistanceForMode: Double
        switch navigationMode {
        case .gpsReliable:
            minimumDistanceForMode = minDistanceReliable
        case .gpsDegrading:
            minimumDistanceForMode = minDistanceDegrading
        case .gpsUnreliable:
            minimumDistanceForMode = minDistanceUnreliable
        }
        guard distanceMoved >= minimumDistanceForMode else { return }
        
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
            confidenceScore: confidenceScore
        )
        
        memory.breadcrumbs.append(crumb)
        totalTrackedDistance += distanceMoved
        trackedDistance = totalTrackedDistance
        try? context.save()
        
        lastRecordedLocation = newLocation
        lastRecordedAltitude = newLocation.altitude
        print("Breadcrumb recorded: \(memory.breadcrumbs.count) total")
        
        if totalTrackedDistance >= maxTrailDistance {
            print("BreadcrumbManager: stopped after distance cap \(Int(totalTrackedDistance))m")
            stop(reason: .distanceCap)
        }
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
