//
//  BreadcrumbPoint.swift
//  Recall
//
//  Created by Giovanni Icasiano on 04/04/2026.
//

import Foundation
import CoreLocation
import SwiftData

@Model
class BreadcrumbPoint {
    var latitude: Double
    var longitude: Double
    var heading: Double
    var stepDistance: Double = 0
    var horizontalAccuracy: Double?
    var speed: Double?
    var course: Double?
    var altitude: Double?
    var verticalAccuracy: Double?
    var verticalDelta: Double?
    var confidenceScore: Double?
    var timestamp: Date
    
    init(
        latitude: Double,
        longitude: Double,
        heading: Double,
        stepDistance: Double = 0,
        horizontalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil,
        verticalDelta: Double? = nil,
        confidenceScore: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.stepDistance = stepDistance
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.verticalDelta = verticalDelta
        self.confidenceScore = confidenceScore
        self.timestamp = Date()
    }
    
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
