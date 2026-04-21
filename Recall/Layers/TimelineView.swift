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

    private func runDebugSimulation(_ profile: SimulationProfile) {
        guard !isRunningSimulation else { return }
        guard let start = locationManager.currentLocation else {
            simulationStatus = "Simulation failed: no current location"
            return
        }
        isRunningSimulation = true
        simulationStatus = "Running turn-route simulation (\(profile.label))..."

        let memory = makeSimulationMemory(from: start, profile: profile)
        modelContext.insert(memory)
        try? modelContext.save()
        let headings = simulationRouteHeadings()
        let stepDistance = 4.5
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
                BreadcrumbManager.shared.ingestSimulatedEstimatedMovement(
                    distanceMeters: stepDistance * 0.92,
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

    private func simulationRouteHeadings() -> [Double] {
        // Pattern: straight, left, straight, right, straight, right, straight, left, straight.
        // Repeat each segment twice and run two cycles for a longer walking scenario.
        let basePattern: [Double] = [0, 90, 0, 270, 0, 270, 0, 90, 0]
        let singleCycle = basePattern.flatMap { heading in [heading, heading] }
        return singleCycle + singleCycle
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

    private func shouldDropSignal(for profile: SimulationProfile, step: Int, totalSteps: Int) -> Bool {
        let progress = Double(step) / Double(max(totalSteps, 1))
        switch profile {
        case .good:
            return false
        case .mixed:
            if progress < 0.35 { return [5, 9, 12].contains(step) }
            if progress < 0.7 { return [18, 23].contains(step) }
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
            let offsets: [Double] = [-8, -4, 0, 4, 7]
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
