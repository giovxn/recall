//
//  RecallApp.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import SwiftUI
import SwiftData
import AppIntents

@main
struct RecallApp: App {
    private let sharedModelContainer: ModelContainer
    
    init() {
        let schema = Schema([MemoryNode.self, BreadcrumbPoint.self])
        do {
            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
            )
        } catch {
            print("SwiftData disk container failed: \(error)")
            do {
                sharedModelContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
                print("SwiftData fallback: using in-memory container")
            } catch {
                fatalError("SwiftData fallback container failed: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
}
