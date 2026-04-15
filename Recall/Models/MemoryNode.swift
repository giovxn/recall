//
//  MemoryNode.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import Foundation
import CoreLocation
import SwiftData
import UIKit
import MapKit

@Model
class MemoryNode {
    var id: UUID
    var imageData: Data
    var latitude: Double
    var longitude: Double
    var captureHorizontalAccuracy: Double?
    var captureAltitude: Double?
    var captureVerticalAccuracy: Double?
    var heading: Double
    var timestamp: Date
    var breadcrumbs: [BreadcrumbPoint]
    var gpsRecoveredAt: Date?
    var gpsRecoveredLatitude: Double?
    var gpsRecoveredLongitude: Double?
    var refinedLatitude: Double?
    var refinedLongitude: Double?
    var refinedTrailLatitudes: [Double]
    var refinedTrailLongitudes: [Double]
    var refinementMode: String
    
    // Vision analysis
    var classification: String
    var smartLabel: String
    var detectedText: [String]
    var dominantColorHex: String
    
    init(
        imageData: Data,
        latitude: Double,
        longitude: Double,
        heading: Double,
        captureHorizontalAccuracy: Double? = nil
    ) {
        self.id = UUID()
        self.imageData = imageData
        self.latitude = latitude
        self.longitude = longitude
        self.captureHorizontalAccuracy = captureHorizontalAccuracy
        self.captureAltitude = nil
        self.captureVerticalAccuracy = nil
        self.heading = heading
        self.timestamp = Date()
        self.breadcrumbs = []
        self.gpsRecoveredAt = nil
        self.gpsRecoveredLatitude = nil
        self.gpsRecoveredLongitude = nil
        self.refinedLatitude = nil
        self.refinedLongitude = nil
        self.refinedTrailLatitudes = []
        self.refinedTrailLongitudes = []
        self.refinementMode = "none"
        self.classification = "memory"
        self.smartLabel = "Memory"
        self.detectedText = []
        self.dominantColorHex = "#0A84FF"
    }
    
    var location: CLLocation {
        if let refinedLatitude, let refinedLongitude {
            return CLLocation(latitude: refinedLatitude, longitude: refinedLongitude)
        }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var originalLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var hasRefinedLocation: Bool {
        refinedLatitude != nil && refinedLongitude != nil
    }
    
    var hasRefinedTrail: Bool {
        !refinedTrailLatitudes.isEmpty && refinedTrailLatitudes.count == refinedTrailLongitudes.count
    }
    
    var refinedTrailCoordinates: [CLLocationCoordinate2D] {
        let count = min(refinedTrailLatitudes.count, refinedTrailLongitudes.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            CLLocationCoordinate2D(
                latitude: refinedTrailLatitudes[index],
                longitude: refinedTrailLongitudes[index]
            )
        }
    }
    
    var dominantColor: UIColor {
        UIColor(hex: dominantColorHex) ?? .systemBlue
    }
}

// MARK: - UIColor hex extension
extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
    
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
