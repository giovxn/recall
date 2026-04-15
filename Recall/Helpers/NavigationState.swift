//
//  NavigationState.swift
//  Recall
//
//  Created by Giovanni Icasiano on 04/04/2026.
//

import Foundation
import Combine

class NavigationState: ObservableObject {
    static let shared = NavigationState()
    
    @Published var selectedTab: Int = 0
}

enum NavigationMode: String {
    case gpsReliable
    case gpsDegrading
    case gpsUnreliable
}

final class NavigationStateManager: ObservableObject {
    static let shared = NavigationStateManager()

    @Published private(set) var currentMode: NavigationMode = .gpsDegrading
    
    private var pendingMode: NavigationMode?
    private var pendingModeSampleCount: Int = 0
    private var lastModeChangeAt: Date = .distantPast
    
    private let requiredSamplesForSwitch = 3
    private let minimumModeHold: TimeInterval = 5.0

    func updateMode(from confidence: LocationConfidenceLevel) {
        let next: NavigationMode
        switch confidence {
        case .high:
            next = .gpsReliable
        case .medium:
            next = .gpsDegrading
        case .low:
            next = .gpsUnreliable
        }
        
        guard next != currentMode else {
            pendingMode = nil
            pendingModeSampleCount = 0
            return
        }
        
        let now = Date()
        let elapsedSinceLastChange = now.timeIntervalSince(lastModeChangeAt)
        guard elapsedSinceLastChange >= minimumModeHold else { return }
        
        if pendingMode == next {
            pendingModeSampleCount += 1
        } else {
            pendingMode = next
            pendingModeSampleCount = 1
        }
        
        guard pendingModeSampleCount >= requiredSamplesForSwitch else { return }
        currentMode = next
        lastModeChangeAt = now
        pendingMode = nil
        pendingModeSampleCount = 0
    }
}
