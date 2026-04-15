//
//  DirectionHelper.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import Foundation
import CoreLocation

struct DirectionHelper {
    
    static func distance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
    
    static func distanceString(from: CLLocation, to: CLLocation) -> String {
        let meters = distance(from: from, to: to)
        if meters < 1000 {
            return "~\(Int(meters))m"
        } else {
            let km = meters / 1000
            return String(format: "~%.1fkm", km)
        }
    }
    
    static func bearing(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude.toRadians()
        let lat2 = to.coordinate.latitude.toRadians()
        let dLon = (to.coordinate.longitude - from.coordinate.longitude).toRadians()
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        let radiansBearing = atan2(y, x)
        return (radiansBearing.toDegrees() + 360).truncatingRemainder(dividingBy: 360)
    }
    
    static func relativeArrow(bearing: Double, currentHeading: Double) -> String {
        var relative = bearing - currentHeading
        if relative < 0 { relative += 360 }
        
        switch relative {
        case 337.5...360, 0..<22.5:   return "↑"
        case 22.5..<67.5:             return "↗"
        case 67.5..<112.5:            return "→"
        case 112.5..<157.5:           return "↘"
        case 157.5..<202.5:           return "↓"
        case 202.5..<247.5:           return "↙"
        case 247.5..<292.5:           return "←"
        case 292.5..<337.5:           return "↖"
        default:                       return "↑"
        }
    }
}

private extension Double {
    func toRadians() -> Double { self * .pi / 180 }
    func toDegrees() -> Double { self * 180 / .pi }
}
