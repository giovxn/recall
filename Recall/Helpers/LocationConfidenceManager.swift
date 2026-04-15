import Foundation
import CoreLocation
import Combine

enum LocationConfidenceLevel: String {
    case high
    case medium
    case low
}

final class LocationConfidenceManager: ObservableObject {
    static let shared = LocationConfidenceManager()

    @Published private(set) var currentConfidence: LocationConfidenceLevel = .medium
    @Published private(set) var confidenceScore: Double = 0.5

    private var recent: [CLLocation] = []
    private var lastConfidence: LocationConfidenceLevel = .medium
    private let sampleWindow = 8

    func ingest(_ location: CLLocation) {
        guard location.horizontalAccuracy > 0 else { return }
        recent.append(location)
        if recent.count > sampleWindow {
            recent.removeFirst(recent.count - sampleWindow)
        }

        let accuracy = location.horizontalAccuracy
        let jitter = coordinateStdDevMeters(locations: recent)
        let jumpiness = jumpScore(locations: recent)
        let speedVar = speedVariance(locations: recent)

        var score = 1.0
        score -= normalized(accuracy, low: 8, high: 50) * 0.52
        score -= normalized(jitter, low: 3, high: 30) * 0.23
        score -= jumpiness * 0.15
        score -= normalized(speedVar, low: 0.4, high: 4.0) * 0.10
        score = max(0, min(1, score))
        confidenceScore = score

        let next: LocationConfidenceLevel
        if accuracy < 12, jitter < 8, jumpiness < 0.35 {
            next = .high
        } else if accuracy > 30 || jumpiness > 0.65 || score < 0.34 {
            next = .low
        } else {
            next = .medium
        }

        // Hysteresis: don't flip rapidly around thresholds.
        if next == .low, lastConfidence == .high, score > 0.42 {
            return
        }
        if next == .high, lastConfidence == .low, score < 0.58 {
            return
        }

        currentConfidence = next
        lastConfidence = next
    }

    private func coordinateStdDevMeters(locations: [CLLocation]) -> Double {
        guard locations.count >= 3 else { return 0 }
        let lats = locations.map(\.coordinate.latitude)
        let lons = locations.map(\.coordinate.longitude)
        let meanLat = lats.reduce(0, +) / Double(lats.count)
        let meanLon = lons.reduce(0, +) / Double(lons.count)
        let latVar = lats.map { ($0 - meanLat) * ($0 - meanLat) }.reduce(0, +) / Double(lats.count)
        let lonVar = lons.map { ($0 - meanLon) * ($0 - meanLon) }.reduce(0, +) / Double(lons.count)

        // Rough meters conversion.
        let latMeters = sqrt(latVar) * 111_320
        let lonMeters = sqrt(lonVar) * 111_320 * cos(meanLat * .pi / 180)
        return sqrt((latMeters * latMeters) + (lonMeters * lonMeters))
    }

    private func jumpScore(locations: [CLLocation]) -> Double {
        guard locations.count >= 3 else { return 0 }
        var jumps = 0
        for i in 1..<locations.count {
            let dt = max(0.4, locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp))
            let d = locations[i].distance(from: locations[i - 1])
            let v = d / dt
            if d > 30 || v > 6.0 {
                jumps += 1
            }
        }
        return Double(jumps) / Double(max(1, locations.count - 1))
    }

    private func speedVariance(locations: [CLLocation]) -> Double {
        let speeds = locations.compactMap { $0.speed >= 0 ? $0.speed : nil }
        guard speeds.count >= 3 else { return 0 }
        let mean = speeds.reduce(0, +) / Double(speeds.count)
        return speeds.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(speeds.count)
    }

    private func normalized(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else { return 0 }
        return max(0, min(1, (value - low) / (high - low)))
    }
}
