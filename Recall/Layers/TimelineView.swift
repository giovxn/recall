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
                    
                    Button {
                        createDebugMemory()
                    } label: {
                        Label("Debug", systemImage: "ant.fill")
                    }
                    .tint(.orange)
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
            modelContext.delete(memories[index])
        }
    }
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
