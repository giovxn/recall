//
//  TimelineView.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import PhotosUI
import UIKit
import ImageIO

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryNode.timestamp, order: .reverse) private var memories: [MemoryNode]
    @StateObject private var locationManager = LocationManager()
    @State private var showManualMemorySheet = false
    @State private var editingMemory: MemoryNode?
#if DEBUG
    @State private var isRunningSimulation = false
    @State private var simulationStatus: String?
#endif
    
    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No memories yet")
                            .foregroundStyle(.secondary)
                        Text("Tap Capture to save your first one")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        ForEach(memories) { memory in
                            NavigationLink(destination: FindItView(memory: memory)) {
                                MemoryRow(memory: memory)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    LiveActivityManager.shared.endActivity(for: memory.id)
                                    modelContext.delete(memory)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                Button {
                                    editingMemory = memory
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteMemories)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recall")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showManualMemorySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
#if DEBUG
                    Menu {
                        Button("Create static debug memory") {
                            createDebugMemory()
                        }
                        Divider()
                        Button("Run 40m simulation (good GPS)") {
                            runDebugSimulation(.good)
                        }
                        .disabled(isRunningSimulation)
                        Button("Run 40m simulation (mixed GPS)") {
                            runDebugSimulation(.mixed)
                        }
                        .disabled(isRunningSimulation)
                        Button("Run 40m simulation (poor GPS)") {
                            runDebugSimulation(.poor)
                        }
                        .disabled(isRunningSimulation)
                        Divider()
                        Button("Run curved-path simulation (mixed GPS)") {
                            runDebugSimulation(.mixed, route: .curvedPark)
                        }
                        .disabled(isRunningSimulation)
                        Button("Run out-and-back simulation (mixed GPS)") {
                            runDebugSimulation(.mixed, route: .outAndBack)
                        }
                        .disabled(isRunningSimulation)
                        Divider()
                        Button("Benchmark: underground parking (good vs mixed)") {
                            runOverlayComparisonSimulation(.parkingExitSimple)
                        }
                        .disabled(isRunningSimulation)
                        Button("Benchmark: urban canyon (good vs mixed)") {
                            runOverlayComparisonSimulation(.parkingToMallSimple)
                        }
                        .disabled(isRunningSimulation)
                        Button("Benchmark: complex long route (good vs mixed)") {
                            runOverlayComparisonSimulation(.complexLong)
                        }
                        .disabled(isRunningSimulation)
                    } label: {
                        if isRunningSimulation {
                            Label("Running", systemImage: "dot.radiowaves.left.and.right")
                        } else {
                            Label("Debug", systemImage: "ant.fill")
                        }
                    }
                    .tint(.orange)
#endif
                }
            }
        }
        .sheet(isPresented: $showManualMemorySheet) {
            ManualMemorySheet(modelContext: modelContext)
        }
        .sheet(item: $editingMemory) { memory in
            EditMemorySheet(memory: memory, modelContext: modelContext)
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()
        }
#if DEBUG
        .safeAreaInset(edge: .bottom) {
            if let simulationStatus {
                Text(simulationStatus)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)
            }
        }
#endif
    }
    
    // Creates a fake memory 80m north of your current location
    private func createDebugMemory() {
        guard let location = locationManager.currentLocation else {
            print("DEBUG: no location yet")
            return
        }
        
        let offsetMeters: Double = 80
        let earthRadius: Double = 6371000
        let dLat = offsetMeters / earthRadius * (180 / .pi)
        
        let fakeLat = location.coordinate.latitude + dLat
        let fakeLon = location.coordinate.longitude
        
        // Create a simple colored image as placeholder
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        let fakeImage = renderer.image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            let text = "DEBUG" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 40),
                .foregroundColor: UIColor.white
            ]
            text.draw(at: CGPoint(x: 80, y: 130), withAttributes: attrs)
        }
        
        let memory = MemoryNode(
            imageData: fakeImage.jpegData(compressionQuality: 0.8) ?? Data(),
            latitude: fakeLat,
            longitude: fakeLon,
            heading: 0,
            captureHorizontalAccuracy: 5
        )
        
        // Add some fake breadcrumbs between you and the pin
        for i in 1...4 {
            let fraction = Double(i) / 5.0
            let crumbLat = location.coordinate.latitude + (dLat * fraction)
            let crumb = BreadcrumbPoint(
                latitude: crumbLat,
                longitude: fakeLon,
                heading: 0,
                stepDistance: offsetMeters / 5.0
            )
            memory.breadcrumbs.append(crumb)
        }
        
        modelContext.insert(memory)
        print("DEBUG: created fake memory 80m north at \(fakeLat), \(fakeLon)")
    }
    
    private func deleteMemories(at offsets: IndexSet) {
        for index in offsets {
            let memory = memories[index]
            LiveActivityManager.shared.endActivity(for: memory.id)
            modelContext.delete(memory)
        }
    }

#if DEBUG
    private enum SimulationProfile {
        case good
        case mixed
        case poor

        var label: String {
            switch self {
            case .good: return "good GPS"
            case .mixed: return "mixed GPS"
            case .poor: return "poor GPS"
            }
        }

        var baseAccuracy: Double {
            switch self {
            case .good: return 8
            case .mixed: return 24
            case .poor: return 55
            }
        }
    }

    private enum SimulationRoute {
        case cityBlocks
        case curvedPark
        case outAndBack

        var label: String {
            switch self {
            case .cityBlocks: return "city blocks"
            case .curvedPark: return "curved park path"
            case .outAndBack: return "out and back"
            }
        }
    }

    private enum OverlayRoute {
        case parkingExitSimple
        case parkingToMallSimple
        case complexLong

        var label: String {
            switch self {
            case .parkingExitSimple: return "parking exit simple"
            case .parkingToMallSimple: return "parking to mall simple"
            case .complexLong: return "complex long route"
            }
        }

        var stepDistance: Double {
            switch self {
            case .parkingExitSimple: return 4.4
            case .parkingToMallSimple: return 4.6
            case .complexLong: return 4.8
            }
        }

        var routeHeadings: [Double] {
            switch self {
            case .parkingExitSimple:
                // Straight aisle -> left turn -> straight -> right turn -> mall entry.
                return [0, 0, 0, 90, 90, 90, 0, 0, 270, 270, 270, 0, 0]
            case .parkingToMallSimple:
                // Ramp out + two easy turns, realistic for parking-to-entrance flow.
                return [0, 10, 18, 25, 32, 40, 60, 80, 90, 90, 90, 45, 20, 0, 0, 0]
            case .complexLong:
                // Long route with mixed straights, bends and block-like turns.
                return [
                    0, 0, 0, 15, 25, 35, 45, 55, 65, 75, 85, 90, 90, 90,
                    70, 50, 30, 10, 0, 0, 340, 320, 300, 280, 270, 270,
                    285, 300, 320, 340, 0, 20, 40, 60, 80, 100, 120, 140,
                    160, 180, 180, 165, 150, 135, 120, 105, 90, 90, 90, 70,
                    50, 30, 15, 0, 0, 350, 340, 330, 320, 300
                ]
            }
        }

        var dropoutSteps: Set<Int> {
            switch self {
            case .parkingExitSimple:
                return [4, 5, 9]
            case .parkingToMallSimple:
                return [6, 7, 11]
            case .complexLong:
                return [8, 9, 16, 17, 24, 25, 37, 38, 49, 50]
            }
        }

        var headingOffsets: [Double] {
            switch self {
            case .parkingExitSimple: return [-6, -3, 0, 2, 4]
            case .parkingToMallSimple: return [-5, -2, 0, 2, 4]
            case .complexLong: return [-7, -4, -1, 0, 2, 5]
            }
        }
    }

    private func runDebugSimulation(_ profile: SimulationProfile, route: SimulationRoute = .cityBlocks) {
        guard !isRunningSimulation else { return }
        guard let start = locationManager.currentLocation else {
            simulationStatus = "Simulation failed: no current location"
            return
        }
        isRunningSimulation = true
        simulationStatus = "Running \(route.label) simulation (\(profile.label))..."

        let memory = makeSimulationMemory(from: start, profile: profile)
        modelContext.insert(memory)
        try? modelContext.save()
        let headings = simulationRouteHeadings(route: route)
        let stepDistance = simulationStepDistance(for: route)
        let startTime = Date()
        BreadcrumbManager.shared.start(for: memory, context: modelContext)
        runSimulationStep(
            step: 1,
            routeHeadings: headings,
            currentLocation: start,
            memory: memory,
            profile: profile,
            stepDistance: stepDistance,
            startTime: startTime
        )
    }

    private func runOverlayComparisonSimulation(_ route: OverlayRoute) {
        guard !isRunningSimulation else { return }
        guard let start = locationManager.currentLocation else {
            simulationStatus = "Overlay simulation failed: no current location"
            return
        }
        isRunningSimulation = true
        simulationStatus = "Running overlay simulation (\(route.label))..."

        let memory = makeSimulationMemory(from: start, profile: .mixed)
        memory.smartLabel = "Overlay benchmark - \(route.label)"
        memory.classification = "place"
        modelContext.insert(memory)
        try? modelContext.save()

        let headings = route.routeHeadings
        let stepDistance = route.stepDistance
        var truthLocation = start
        var mixedLocation = start
        var goodLocations: [CLLocation] = []
        var mixedLocations: [CLLocation] = []
        var mixedEstimatedCount = 0
        let goodSegmentID = UUID()
        var mixedSegmentID = UUID()
        var inDrop = false

        func stepSimulation(_ index: Int) {
            guard index < headings.count else {
                let metrics = benchmarkMetrics(good: goodLocations, mixed: mixedLocations)
                let mixedEstimatedRatio = mixedLocations.isEmpty ? 0 : Int((Double(mixedEstimatedCount) / Double(mixedLocations.count)) * 100)
                let mixedSegments = Set(memory.breadcrumbs.filter(\.isEstimated).compactMap(\.segmentID)).count
                simulationStatus = "Overlay \(route.label): mean err \(Int(metrics.meanError))m, end err \(Int(metrics.endError))m, est \(mixedEstimatedRatio)%, seg \(max(1, mixedSegments))"
                isRunningSimulation = false
                try? modelContext.save()
                return
            }

            let heading = headings[index]
            let trueCoord = projectedCoordinate(
                from: truthLocation.coordinate,
                headingDegrees: heading,
                distanceMeters: stepDistance
            )
            truthLocation = CLLocation(latitude: trueCoord.latitude, longitude: trueCoord.longitude)

            let goodCoord = noisyCoordinate(base: trueCoord, index: index, maxNoiseMeters: 0.8)
            let goodPoint = BreadcrumbPoint(
                latitude: goodCoord.latitude,
                longitude: goodCoord.longitude,
                heading: heading,
                stepDistance: stepDistance,
                horizontalAccuracy: 8,
                speed: 1.4,
                course: heading,
                altitude: start.altitude,
                verticalAccuracy: 8,
                verticalDelta: 0,
                confidenceScore: 0.92,
                segmentID: goodSegmentID,
                isEstimated: false
            )
            memory.breadcrumbs.append(goodPoint)
            goodLocations.append(goodPoint.location)

            let stepNumber = index + 1
            let shouldDrop = route.dropoutSteps.contains(stepNumber)
            if shouldDrop {
                if !inDrop {
                    mixedSegmentID = UUID()
                    inDrop = true
                }
                let offset = route.headingOffsets[index % route.headingOffsets.count]
                let estimatedHeading = normalizeHeading(heading + offset)
                let estimatedCoord = projectedCoordinate(
                    from: mixedLocation.coordinate,
                    headingDegrees: estimatedHeading,
                    distanceMeters: stepDistance * 0.94
                )
                let mixedPoint = BreadcrumbPoint(
                    latitude: estimatedCoord.latitude,
                    longitude: estimatedCoord.longitude,
                    heading: estimatedHeading,
                    stepDistance: stepDistance * 0.94,
                    horizontalAccuracy: nil,
                    speed: nil,
                    course: nil,
                    altitude: start.altitude,
                    verticalAccuracy: nil,
                    verticalDelta: 0,
                    confidenceScore: 0.28,
                    segmentID: mixedSegmentID,
                    isEstimated: true
                )
                memory.breadcrumbs.append(mixedPoint)
                mixedLocations.append(mixedPoint.location)
                mixedEstimatedCount += 1
                mixedLocation = mixedPoint.location
            } else {
                if inDrop {
                    mixedSegmentID = UUID()
                    inDrop = false
                }
                let mixedCoord = noisyCoordinate(base: trueCoord, index: index + 1000, maxNoiseMeters: 2.8)
                let mixedPoint = BreadcrumbPoint(
                    latitude: mixedCoord.latitude,
                    longitude: mixedCoord.longitude,
                    heading: heading,
                    stepDistance: stepDistance,
                    horizontalAccuracy: 24,
                    speed: 1.35,
                    course: heading,
                    altitude: start.altitude,
                    verticalAccuracy: 10,
                    verticalDelta: 0,
                    confidenceScore: 0.64,
                    segmentID: mixedSegmentID,
                    isEstimated: false
                )
                memory.breadcrumbs.append(mixedPoint)
                mixedLocations.append(mixedPoint.location)
                mixedLocation = mixedPoint.location
            }

            try? modelContext.save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                stepSimulation(index + 1)
            }
        }

        stepSimulation(0)
    }

    private func runSimulationStep(
        step: Int,
        routeHeadings: [Double],
        currentLocation: CLLocation,
        memory: MemoryNode,
        profile: SimulationProfile,
        stepDistance: Double,
        startTime: Date
    ) {
        guard step <= routeHeadings.count else {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            simulationStatus = simulationSummary(memory: memory, elapsedSeconds: elapsed, profile: profile)
            BreadcrumbManager.shared.stop(reason: .manual)
            isRunningSimulation = false
            try? modelContext.save()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let heading = routeHeadings[step - 1]
            let nextLocation = simulatedNextLocation(
                from: currentLocation,
                headingDegrees: heading,
                distanceMeters: stepDistance,
                accuracyMeters: simulatedAccuracy(for: profile, step: step, totalSteps: routeHeadings.count)
            )

            // Simulate occasional GPS loss under mixed/poor conditions.
            let shouldDropSignal = shouldDropSignal(for: profile, step: step, totalSteps: routeHeadings.count)
            if !shouldDropSignal {
                BreadcrumbManager.shared.ingestSimulatedLocation(nextLocation, heading: heading)
            } else {
                if shouldEmitEstimatedCrumb(for: profile, step: step) {
                let estimatedHeading = simulatedEstimatedHeading(
                    profile: profile,
                    trueHeading: heading,
                    step: step,
                    totalSteps: routeHeadings.count
                )
                let estimatedDistanceScale: Double = {
                    switch profile {
                    case .good: return 1.0
                    case .mixed: return 0.96
                    case .poor: return 0.9
                    }
                }()
                BreadcrumbManager.shared.ingestSimulatedEstimatedMovement(
                    distanceMeters: stepDistance * estimatedDistanceScale,
                    heading: estimatedHeading
                )
                }
            }

            runSimulationStep(
                step: step + 1,
                routeHeadings: routeHeadings,
                currentLocation: nextLocation,
                memory: memory,
                profile: profile,
                stepDistance: stepDistance,
                startTime: startTime
            )
        }
    }

    private func makeSimulationMemory(from location: CLLocation, profile: SimulationProfile) -> MemoryNode {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320))
        let image = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let text = "SIM \(profile.label.uppercased())" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white
            ]
            text.draw(at: CGPoint(x: 20, y: 140), withAttributes: attrs)
        }
        let memory = MemoryNode(
            imageData: image.jpegData(compressionQuality: 0.82) ?? Data(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            heading: 0,
            captureHorizontalAccuracy: profile.baseAccuracy
        )
        memory.smartLabel = "Simulation - \(profile.label)"
        memory.classification = "place"
        memory.refinementMode = "none"
        return memory
    }

    private func simulationRouteHeadings(route: SimulationRoute) -> [Double] {
        switch route {
        case .cityBlocks:
            // Grid-walk style turns.
            let basePattern: [Double] = [0, 90, 90, 0, 270, 270, 0, 90, 0]
            return basePattern.flatMap { [$0, $0] } + [0, 0, 90, 90]
        case .curvedPark:
            // Gradual bends like walking paths.
            return [
                0, 8, 15, 22, 30,
                42, 55, 70, 82, 95,
                102, 110, 118, 126, 134,
                142, 150, 158, 165, 172,
                180, 188, 196, 205, 214,
                220, 226, 232, 238, 245
            ]
        case .outAndBack:
            // Straight outward leg, turn-around arc, then return with slight drift.
            let outward = Array(repeating: 0.0, count: 10)
            let turnArc: [Double] = [20, 45, 75, 110, 145, 175]
            let inbound = Array(repeating: 182.0, count: 10)
            return outward + turnArc + inbound
        }
    }

    private func simulationStepDistance(for route: SimulationRoute) -> Double {
        switch route {
        case .cityBlocks: return 4.8
        case .curvedPark: return 4.2
        case .outAndBack: return 5.0
        }
    }

    private func simulatedAccuracy(for profile: SimulationProfile, step: Int, totalSteps: Int) -> Double {
        let progress = Double(step) / Double(max(totalSteps, 1))
        switch profile {
        case .good:
            let wobble = Double((step % 5) - 2)
            return max(5, 8 + wobble)
        case .mixed:
            // Gradually improves from degraded GPS to near-good by end of walk.
            let baseline = 36 - (progress * 14) // ~36m -> ~22m
            let wobble = Double((step % 6) - 3) * 2
            return max(15, baseline + wobble)
        case .poor:
            // Starts very noisy, then recovers late in the walk.
            let baseline = 72 - (progress * 42) // ~72m -> ~30m
            let wobble = Double((step % 7) - 3) * 3
            return max(18, baseline + wobble)
        }
    }

    private func noisyCoordinate(
        base: CLLocationCoordinate2D,
        index: Int,
        maxNoiseMeters: Double
    ) -> CLLocationCoordinate2D {
        let pseudo = sin(Double(index) * 1.73) * maxNoiseMeters
        let heading = normalizeHeading(Double((index * 37) % 360))
        return projectedCoordinate(from: base, headingDegrees: heading, distanceMeters: abs(pseudo))
    }

    private func benchmarkMetrics(good: [CLLocation], mixed: [CLLocation]) -> (meanError: Double, endError: Double) {
        let paired = min(good.count, mixed.count)
        guard paired > 0 else { return (0, 0) }
        let total = (0..<paired).reduce(0.0) { sum, i in
            sum + good[i].distance(from: mixed[i])
        }
        let mean = total / Double(paired)
        let end = good[paired - 1].distance(from: mixed[paired - 1])
        return (mean, end)
    }

    private func shouldDropSignal(for profile: SimulationProfile, step: Int, totalSteps: Int) -> Bool {
        let progress = Double(step) / Double(max(totalSteps, 1))
        switch profile {
        case .good:
            return false
        case .mixed:
            if progress < 0.35 { return [6, 11].contains(step) }
            if progress < 0.7 { return [18].contains(step) }
            return false
        case .poor:
            if progress < 0.5 { return [4, 5, 8, 9, 12, 13, 16].contains(step) }
            if progress < 0.8 { return [22, 25, 28].contains(step) }
            return false
        }
    }

    private func simulationSummary(memory: MemoryNode, elapsedSeconds: Int, profile: SimulationProfile) -> String {
        let crumbs = memory.breadcrumbs.count
        let estimated = memory.breadcrumbs.filter(\.isEstimated).count
        let segmentCount = Set(memory.breadcrumbs.compactMap(\.segmentID)).count
        let maxJump = memory.breadcrumbs.map(\.stepDistance).max() ?? 0
        return "Done \(profile.label): \(crumbs) crumbs, \(estimated) est, \(max(segmentCount, 1)) segments, max jump \(Int(maxJump))m, \(elapsedSeconds)s"
    }

    private func simulatedEstimatedHeading(profile: SimulationProfile, trueHeading: Double, step: Int, totalSteps: Int) -> Double {
        let progress = Double(step) / Double(max(totalSteps, 1))
        switch profile {
        case .good:
            return trueHeading
        case .mixed:
            let offsets: [Double] = [-5, -2, 0, 2, 4]
            return normalizeHeading(trueHeading + offsets[step % offsets.count])
        case .poor:
            let offsets: [Double] = progress < 0.7
                ? [-16, -10, -5, 0, 6, 11, 15]
                : [-10, -6, -3, 0, 4, 7, 9]
            return normalizeHeading(trueHeading + offsets[step % offsets.count])
        }
    }

    private func shouldEmitEstimatedCrumb(for profile: SimulationProfile, step: Int) -> Bool {
        switch profile {
        case .good:
            return false
        case .mixed:
            return true
        case .poor:
            // Reduce zig-zag density in worst profile.
            return step.isMultiple(of: 2)
        }
    }

    private func normalizeHeading(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private func simulatedNextLocation(
        from location: CLLocation,
        headingDegrees: Double,
        distanceMeters: Double,
        accuracyMeters: Double
    ) -> CLLocation {
        let coordinate = projectedCoordinate(
            from: location.coordinate,
            headingDegrees: headingDegrees,
            distanceMeters: distanceMeters
        )
        return CLLocation(
            coordinate: coordinate,
            altitude: location.altitude,
            horizontalAccuracy: accuracyMeters,
            verticalAccuracy: max(location.verticalAccuracy, 8),
            course: headingDegrees,
            speed: 1.5,
            timestamp: Date()
        )
    }

    private func projectedCoordinate(
        from coordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        distanceMeters: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = headingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius
        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
#endif
}

struct MemoryRow: View {
    let memory: MemoryNode
    
    var body: some View {
        HStack(spacing: 12) {
            if let image = UIImage(data: memory.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) {
                        ClassificationBadge(classification: memory.classification)
                            .offset(x: -4, y: 4)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.smartLabel)
                    .font(.system(size: 15, weight: .semibold))
                
                Text(memory.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !memory.detectedText.isEmpty {
                    Text(memory.detectedText.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                if !memory.breadcrumbs.isEmpty {
                    Text("\(memory.breadcrumbs.count) breadcrumbs")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ClassificationBadge: View {
    let classification: String
    
    var icon: String {
        switch classification {
        case "parking":  return "car.fill"
        case "luggage":  return "suitcase.fill"
        case "food":     return "fork.knife"
        case "shop":     return "bag.fill"
        case "document": return "doc.fill"
        case "person":   return "person.fill"
        case "place":    return "building.fill"
        default:         return "mappin"
        }
    }
    
    var color: Color {
        switch classification {
        case "parking":  return .blue
        case "luggage":  return .purple
        case "food":     return .orange
        case "shop":     return .pink
        case "document": return .yellow
        case "person":   return .green
        case "place":    return .teal
        default:         return .gray
        }
    }
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(color)
            .clipShape(Circle())
    }
}

struct ManualMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let modelContext: ModelContext
    
    private enum Field: Hashable {
        case name
        case description
        case search
    }
    
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedMapItem: MKMapItem?
    @State private var pinnedCoordinate: CLLocationCoordinate2D?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showPhotoLocationPrompt = false
    @State private var photoLocationCandidate: CLLocationCoordinate2D?
    @FocusState private var focusedField: Field?
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCoordinate != nil && !isSaving
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .description)
                }
                
                Section("Location") {
                    HStack(spacing: 8) {
                        TextField("Search place or address", text: $searchQuery)
                            .focused($focusedField, equals: .search)
                            .submitLabel(.search)
                            .onSubmit {
                                triggerSearch()
                            }
                        Button("Search") {
                            triggerSearch()
                        }
                        .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                    
                    ZStack(alignment: .center) {
                        Map(position: $mapPosition, interactionModes: [.zoom, .pan]) {
                            ForEach(pinAnnotations) { pin in
                                Marker("", coordinate: pin.coordinate)
                                    .tint(.red)
                            }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onMapCameraChange { context in
                            mapRegion = context.region
                        }
                        .onTapGesture {
                            focusedField = nil
                        }
                        
                        // Center crosshair to show where "pin map center" will drop.
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                            .allowsHitTesting(false)
                    }
                    
                    Button {
                        pinnedCoordinate = mapRegion.center
                        selectedMapItem = nil
                    } label: {
                        Label("Pin map center", systemImage: "mappin.and.ellipse")
                    }
                    
                    if isSearching {
                        ProgressView("Searching...")
                    }
                    
                    if let selectedMapItem {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pinned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedMapItem.name ?? "Selected location")
                                .font(.subheadline.weight(.semibold))
                            if let address = locationSubtitle(for: selectedMapItem) {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    ForEach(searchResults, id: \.self) { item in
                        Button {
                            selectedMapItem = item
                            pinnedCoordinate = item.location.coordinate
                            mapRegion = MKCoordinateRegion(
                                center: item.location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                            mapPosition = .region(mapRegion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown place")
                                    .foregroundStyle(.primary)
                                if let subtitle = locationSubtitle(for: item) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                
                Section("Image (Optional)") {
                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label(selectedImageData == nil ? "Choose image" : "Change image", systemImage: "photo")
                    }
                    .onChange(of: photosPickerItem) { _, newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self) {
                                selectedImageData = data
                                if let extracted = extractCoordinateFromImage(data) {
                                    photoLocationCandidate = extracted
                                    showPhotoLocationPrompt = true
                                }
                            }
                        }
                    }
                    
                    if selectedImageData != nil {
                        Text("Image selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .alert("Use photo location?", isPresented: $showPhotoLocationPrompt, presenting: photoLocationCandidate) { coordinate in
                Button("Use") {
                    pinnedCoordinate = coordinate
                    selectedMapItem = nil
                    mapRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    mapPosition = .region(mapRegion)
                }
                Button("Keep current", role: .cancel) {}
            } message: { coordinate in
                Text("This image includes location metadata (\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude))).")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveManualMemory()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .interactiveDismissDisabled(true)
        }
    }
    
    private func triggerSearch() {
        focusedField = nil
        searchTask?.cancel()
        searchTask = Task {
            await runLocationSearch()
        }
    }
    
    private func runLocationSearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        request.region = mapRegion
        
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            searchResults = Array(response.mapItems.prefix(8))
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }
    
    private func saveManualMemory() {
        guard let coordinate = selectedCoordinate else { return }
        isSaving = true
        
        let imageData = selectedImageData ?? placeholderImageData()
        let memory = MemoryNode(
            imageData: imageData,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            heading: 0,
            captureHorizontalAccuracy: nil
        )
        
        memory.classification = "place"
        memory.smartLabel = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.detectedText = trimmedDescription.isEmpty ? [] : [trimmedDescription]
        memory.refinementMode = "none"
        
        modelContext.insert(memory)
        try? modelContext.save()
        dismiss()
    }
    
    private var selectedCoordinate: CLLocationCoordinate2D? {
        if let pinnedCoordinate { return pinnedCoordinate }
        if let selectedMapItem { return selectedMapItem.location.coordinate }
        return nil
    }
    
    private var pinAnnotations: [PinAnnotation] {
        guard let selectedCoordinate else { return [] }
        return [PinAnnotation(coordinate: selectedCoordinate)]
    }
    
    private func locationSubtitle(for item: MKMapItem) -> String? {
        let coordinate = item.location.coordinate
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
    
    private func placeholderImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500))
        let image = renderer.image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 500, height: 500))
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
    
    private func extractCoordinateFromImage(_ data: Data) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let rawLatitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let rawLongitude = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        
        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        
        let latitude = latitudeRef.uppercased() == "S" ? -rawLatitude : rawLatitude
        let longitude = longitudeRef.uppercased() == "W" ? -rawLongitude : rawLongitude
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct PinAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct EditMemorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let memory: MemoryNode
    let modelContext: ModelContext

    @State private var name: String
    @State private var notes: String
    @State private var classification: String
    @State private var showValidationError = false
    @State private var validationMessage = ""

    private let classificationOptions = [
        "parking", "luggage", "food", "shop", "document", "person", "place", "memory"
    ]

    init(memory: MemoryNode, modelContext: ModelContext) {
        self.memory = memory
        self.modelContext = modelContext
        _name = State(initialValue: memory.smartLabel)
        _notes = State(initialValue: memory.detectedText.first ?? "")
        _classification = State(initialValue: memory.classification)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Label", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $classification) {
                        ForEach(classificationOptions, id: \.self) { option in
                            Text(option.capitalized).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Invalid input", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Label cannot be empty."
            showValidationError = true
            return
        }

        memory.smartLabel = trimmedName
        memory.classification = classification
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.detectedText = trimmedNotes.isEmpty ? [] : [trimmedNotes]

        try? modelContext.save()
        dismiss()
    }
}
