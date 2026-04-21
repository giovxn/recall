//
//  LiveActivityManager.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import Foundation
import ActivityKit

class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<RecallLiveActivityAttributes>?
    private var activeMemoryID: UUID?
    
    func startActivity(memory: MemoryNode) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = RecallLiveActivityAttributes(
            memoryID: memory.id,
            memoryTimestamp: memory.timestamp
        )
        let state = RecallLiveActivityAttributes.ContentState(
            distanceText: "Calculating...",
            directionText: "Locating...",
            rotationDegrees: 0,
            gpsLevel: "Medium",
            memoryLabel: memory.smartLabel,
            bgHex: memory.dominantColorHex
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            activeMemoryID = memory.id
            print("Activity ID: \(currentActivity?.id ?? "nil")")
            print("Activity distance: \(currentActivity?.content.state.distanceText ?? "nil")")
            print("Activities count: \(Activity<RecallLiveActivityAttributes>.activities.count)")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    func updateActivity(
        distanceText: String,
        directionText: String,
        rotationDegrees: Double,
        gpsLevel: String,
        memoryLabel: String,
        bgHex: String
    ) {
        Task {
            let state = RecallLiveActivityAttributes.ContentState(
                distanceText: distanceText,
                directionText: directionText,
                rotationDegrees: rotationDegrees,
                gpsLevel: gpsLevel,
                memoryLabel: memoryLabel,
                bgHex: bgHex
            )
            await currentActivity?.update(.init(state: state, staleDate: nil))
        }
    }
    
    func endActivity() {
        Task {
            await currentActivity?.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            currentActivity = nil
            activeMemoryID = nil
        }
    }

    func endActivity(for memoryID: UUID) {
        guard activeMemoryID == memoryID else { return }
        endActivity()
    }
}
