import Foundation
import CoreMotion
import Combine

@MainActor
final class MotionDeadReckoner: ObservableObject {
    private let pedometer = CMPedometer()
    private let motionManager = CMMotionManager()
    
    @Published private(set) var distanceSinceAnchor: Double = 0
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var headingStdDev: Double = 180
    @Published private(set) var isRunning = false
    
    private var cumulativeDistance: Double = 0
    private var anchorDistance: Double = 0
    private var lastPedometerDistance: Double?
    private var headingWindow: [Double] = []
    private let headingWindowLimit = 20
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        if CMPedometer.isDistanceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    self.handlePedometer(data)
                }
            }
        }
        
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handleMotion(motion)
        }
    }
    
    func stop() {
        guard isRunning else { return }
        pedometer.stopUpdates()
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        headingWindow.removeAll()
        headingStdDev = 180
    }
    
    func resetAnchor() {
        anchorDistance = cumulativeDistance
        distanceSinceAnchor = 0
    }
    
    private func handlePedometer(_ data: CMPedometerData) {
        guard let total = data.distance?.doubleValue else { return }
        
        if let last = lastPedometerDistance {
            let delta = max(0, total - last)
            cumulativeDistance += min(delta, 3)
        }
        lastPedometerDistance = total
        distanceSinceAnchor = max(0, cumulativeDistance - anchorDistance)
    }
    
    private func handleMotion(_ motion: CMDeviceMotion) {
        let yawDegrees = motion.attitude.yaw * 180 / .pi
        let normalized = (yawDegrees + 360).truncatingRemainder(dividingBy: 360)
        headingDegrees = normalized
        
        headingWindow.append(normalized)
        if headingWindow.count > headingWindowLimit {
            headingWindow.removeFirst()
        }
        
        let unwrapped = unwrapAngles(headingWindow)
        guard !unwrapped.isEmpty else {
            headingStdDev = 180
            return
        }
        let mean = unwrapped.reduce(0, +) / Double(unwrapped.count)
        let variance = unwrapped.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(unwrapped.count)
        headingStdDev = sqrt(variance)
    }
    
    private func unwrapAngles(_ angles: [Double]) -> [Double] {
        guard let first = angles.first else { return [] }
        var result: [Double] = [first]
        for angle in angles.dropFirst() {
            var candidate = angle
            var delta = candidate - result.last!
            while delta > 180 { candidate -= 360; delta = candidate - result.last! }
            while delta < -180 { candidate += 360; delta = candidate - result.last! }
            result.append(candidate)
        }
        return result
    }
}
