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
}
