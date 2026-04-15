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
    
    func startActivity(memory: MemoryNode, arrow: String, distance: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = RecallLiveActivityAttributes(memoryTimestamp: memory.timestamp)
        let state = RecallLiveActivityAttributes.ContentState(arrow: arrow, distance: distance)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            print("Activity ID: \(currentActivity?.id ?? "nil")")
            print("Activity state: \(currentActivity?.content.state.arrow ?? "nil")")
            print("Activity distance: \(currentActivity?.content.state.distance ?? "nil")")
            print("Activities count: \(Activity<RecallLiveActivityAttributes>.activities.count)")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    func updateActivity(arrow: String, distance: String) {
        Task {
            let state = RecallLiveActivityAttributes.ContentState(arrow: arrow, distance: distance)
            await currentActivity?.update(.init(state: state, staleDate: nil))
        }
    }
    
    func endActivity() {
        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }
}
