//
//  LocationManager.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var recentLocations: [CLLocation] = []
    
    private let recentWindowSeconds: TimeInterval = 4
    private let captureTargetAccuracy: Double = 20
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        
        recentLocations.append(contentsOf: locations)
        let cutoff = Date().addingTimeInterval(-recentWindowSeconds)
        recentLocations.removeAll { $0.timestamp < cutoff }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
    
    func bestRecentLocation() -> CLLocation? {
        let valid = recentLocations.filter { $0.horizontalAccuracy > 0 }
        guard !valid.isEmpty else { return currentLocation }
        
        let top = valid
            .sorted { $0.horizontalAccuracy < $1.horizontalAccuracy }
            .prefix(5)
        
        guard !top.isEmpty else { return currentLocation }
        
        let weighted = top.reduce(
            (lat: 0.0, lon: 0.0, totalWeight: 0.0, altitude: 0.0, vAcc: 0.0, vWeight: 0.0)
        ) { acc, loc in
            let weight = 1.0 / max(loc.horizontalAccuracy, 1)
            let vWeight = loc.verticalAccuracy > 0 ? (1.0 / loc.verticalAccuracy) : 0
            return (
                lat: acc.lat + loc.coordinate.latitude * weight,
                lon: acc.lon + loc.coordinate.longitude * weight,
                totalWeight: acc.totalWeight + weight,
                altitude: acc.altitude + loc.altitude * max(vWeight, 0),
                vAcc: acc.vAcc + max(loc.verticalAccuracy, 0) * max(vWeight, 0),
                vWeight: acc.vWeight + max(vWeight, 0)
            )
        }
        
        guard weighted.totalWeight > 0 else { return currentLocation }
        let coordinate = CLLocationCoordinate2D(
            latitude: weighted.lat / weighted.totalWeight,
            longitude: weighted.lon / weighted.totalWeight
        )
        let horizontalAccuracy = top.map(\.horizontalAccuracy).min() ?? 0
        let altitude = weighted.vWeight > 0 ? (weighted.altitude / weighted.vWeight) : (top.first?.altitude ?? 0)
        let verticalAccuracy = weighted.vWeight > 0 ? (weighted.vAcc / weighted.vWeight) : -1
        
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: top.first?.course ?? -1,
            speed: top.first?.speed ?? -1,
            timestamp: Date()
        )
    }

    func isGoodCaptureFix(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > 0 && location.horizontalAccuracy <= captureTargetAccuracy
    }

    func refineCaptureLocation(
        initialLocation: CLLocation,
        timeout: TimeInterval = 8,
        tickInterval: TimeInterval = 1,
        completion: @escaping (_ bestLocation: CLLocation, _ isHighConfidence: Bool) -> Void
    ) {
        let captureTime = Date()
        let deadline = captureTime.addingTimeInterval(timeout)

        func score(_ location: CLLocation, reference: CLLocation) -> Double {
            guard location.horizontalAccuracy > 0 else { return .greatestFiniteMagnitude }
            let freshnessPenalty = max(0, captureTime.timeIntervalSince(location.timestamp)) * 2.0
            let driftPenalty = min(location.distance(from: reference), 20) * 0.5
            return location.horizontalAccuracy + freshnessPenalty + driftPenalty
        }

        func bestCandidate(reference: CLLocation) -> CLLocation {
            let now = Date()
            let candidates = recentLocations.filter {
                $0.horizontalAccuracy > 0 &&
                abs($0.timestamp.timeIntervalSince(captureTime)) <= timeout &&
                now.timeIntervalSince($0.timestamp) <= timeout + 1
            }
            guard !candidates.isEmpty else { return reference }
            return candidates.min { score($0, reference: reference) < score($1, reference: reference) } ?? reference
        }

        func finalize(with location: CLLocation) {
            DispatchQueue.main.async {
                completion(location, self.isGoodCaptureFix(location))
            }
        }

        let seed = bestRecentLocation() ?? initialLocation
        if isGoodCaptureFix(seed) {
            finalize(with: seed)
            return
        }

        func poll() {
            let best = bestCandidate(reference: initialLocation)
            if isGoodCaptureFix(best) || Date() >= deadline {
                finalize(with: best)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + tickInterval) {
                poll()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + tickInterval) {
            poll()
        }
    }
}
