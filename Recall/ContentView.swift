//
//  ContentView.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var navState = NavigationState.shared
    
    var body: some View {
        TabView(selection: $navState.selectedTab) {
            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera.fill")
                }
                .tag(0)
            
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }
                .tag(1)
        }
        .tint(.white)
    }
}
