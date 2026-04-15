import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct FindItView: View {
    let memory: MemoryNode
    private let memoryImage: UIImage?
    @State private var isSnappedToMap = false
    @State private var isTrackingHeading = false
    @State private var isTrailModeEnabled = false
    @State private var trailWaypointIndex: Int?
    @State private var showModeToast = false
    @State private var modeToastText = ""
    @StateObject private var locationManager = LocationManager()
    @StateObject private var breadcrumbManager = BreadcrumbManager.shared
    @StateObject private var confidenceManager = LocationConfidenceManager.shared
    @StateObject private var navigationStateManager = NavigationStateManager.shared
    @StateObject private var directionalGuidanceManager = DirectionalGuidanceManager.shared
    @State private var lastNavigationMode: NavigationMode = .gpsDegrading
    @State private var lastModeToastAt: Date = .distantPast
    
    private let modeToastCooldown: TimeInterval = 6
    
    init(memory: MemoryNode) {
        self.memory = memory
        self.memoryImage = UIImage(data: memory.imageData)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            mainContent(proxy: proxy)
        }
    }
    
    @ViewBuilder
    private func mainContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if let image = memoryImage {
                    heroStack(image: image, proxy: proxy)
                }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    handleSnapDrag(value, proxy: proxy)
                }
        )
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            mapControlsOverlay
        }
        .overlay(alignment: .bottom) {
            modeToastOverlay
        }
        .onAppear {
            handleAppear()
        }
        .onChange(of: isTrailModeEnabled) { _, isEnabled in
            handleTrailModeChange(isEnabled)
        }
        .onChange(of: locationManager.currentLocation) { _, location in
            handleLocationChange(location)
        }
        .onDisappear {
            handleDisappear()
        }
    }

    @ViewBuilder
    private func heroStack(image: UIImage, proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .top) {
            sharpHeroLayer(image: image)
            blurredBridgeLayer(image: image)
            mapLayer
            topGradientLayer
            snappedOverlayLayer(image: image)
            trackerLayer(proxy: proxy)
        }
                        .frame(maxWidth: .infinity)
                        .id("top")
        
        // MAP anchor point
        Color.clear
            .frame(height: 1)
            .id("map")
            .padding(.top, 200)
    }
    
    private func sharpHeroLayer(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .horizontal)
            .ignoresSafeArea(edges: .top)
            .blur(radius: isSnappedToMap ? 2 : 0)
            .offset(y: isSnappedToMap ? -100 : -220)
            .animation(.easeInOut(duration: 0.2), value: isSnappedToMap)
            .opacity(isSnappedToMap ? 0.7 : 1)
            .allowsHitTesting(false)
    }
    
    private func blurredBridgeLayer(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 920)
            .scaleEffect(x: -1, y: -1)
            .blur(radius: 28)
            .scaleEffect(1.1)
            .brightness(-0.2)
            .clipped()
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                    Rectangle().frame(height: 190)
                }
            )
            .allowsHitTesting(false)
            .drawingGroup()
    }
    
    @ViewBuilder
    private var mapLayer: some View {
        if let rawLocation = locationManager.currentLocation {
            BreadcrumbMapView(
                memory: memory,
                currentLocation: rawLocation,
                isSnappedToMap: isSnappedToMap,
                isTrackingHeading: isTrackingHeading
            )
            .frame(maxWidth: .infinity)
            .frame(height: 670)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: isSnappedToMap ? 570 : 622)
            .animation(.easeInOut(duration: 0.2), value: isSnappedToMap)
            .allowsHitTesting(isSnappedToMap)
        }
    }
    
    private var topGradientLayer: some View {
        LinearGradient(
            colors: [.black.opacity(0.7), .black.opacity(0.15), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: isSnappedToMap ? 80 : 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: 622)
        .opacity(isSnappedToMap ? 0 : 1)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: isSnappedToMap)
    }
    
    private func snappedOverlayLayer(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 920)
            .scaleEffect(x: -1, y: -1)
            .blur(radius: 20)
            .scaleEffect(1.1)
            .brightness(-0.28)
            .opacity(isSnappedToMap ? 1 : 0)
            .clipped()
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                    Rectangle().frame(height: 5)
                    LinearGradient(
                        colors: [.black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
            )
            .allowsHitTesting(false)
            .drawingGroup()
    }
    
    @ViewBuilder
    private func trackerLayer(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 55)
            trackerContent(proxy: proxy)
        }
        .allowsHitTesting(true)
        .frame(maxWidth: .infinity)
        .frame(height: 920)
    }
    
    @ViewBuilder
    private func trackerContent(proxy: ScrollViewProxy) -> some View {
        if let rawLocation = locationManager.currentLocation {
            let savedLocation = navigationTarget(for: rawLocation)
            let bearing = DirectionHelper.bearing(from: rawLocation, to: savedLocation)
            let heading = resolvedHeading(for: rawLocation)
            let distance = DirectionHelper.distance(from: rawLocation, to: savedLocation)
            let distanceStr = DirectionHelper.distanceString(from: rawLocation, to: savedLocation)
            let rotationAngle = bearing - heading
            let _ = { HapticDirectionManager.shared.update(angleDiff: rotationAngle, distance: distance) }()
            
            VStack(spacing: 12) {
                TrackerView(distance: distance, rotationAngle: rotationAngle)
                    .id("tracker-\(isSnappedToMap ? 1 : 0)")
                    .frame(width: 200, height: 200)
                    .padding(.top, isSnappedToMap ? 28 : 16)
                    .allowsHitTesting(!isSnappedToMap)
                    .padding(.bottom, isSnappedToMap ? -34 : 0)
                VStack(spacing: 6) {
                    Text(distanceStr)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(proximityColor(distance: distance))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: distanceStr)
                    if breadcrumbManager.activeMemoryID == memory.id {
                        trailStatusPill
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    if navigationStateManager.currentMode == .gpsUnreliable {
                        Text("Guiding by Direction")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.95))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        Text("\(directionalGuidanceManager.directionText) • ~\(Int(directionalGuidanceManager.relativeDistanceMeters))m")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    Text("GPS \(navigationStateManager.currentMode == .gpsReliable ? "High" : navigationStateManager.currentMode == .gpsDegrading ? "Medium" : "Low") • \(Int(confidenceManager.confidenceScore * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    if memory.hasRefinedLocation {
                        Text("Location refined")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.mint.opacity(0.95))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    Text(proximityLabel(distance: distance))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(isSnappedToMap ? 1 : 0)
                }
                .allowsHitTesting(!isSnappedToMap)
                
                Button {
                    toggleSnapState(proxy: proxy)
                } label: {
                    Image(systemName: isSnappedToMap ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(8)
                }
                .allowsHitTesting(true)
            }
            .onChange(of: distanceStr) {
                LiveActivityManager.shared.updateActivity(
                    arrow: DirectionHelper.relativeArrow(bearing: bearing, currentHeading: heading),
                    distance: distanceStr
                )
            }
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Getting location...")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 60)
        }
    }
    
    @ViewBuilder
    private var mapControlsOverlay: some View {
        if isSnappedToMap {
            VStack(spacing: 10) {
                Button {
                    isTrackingHeading.toggle()
                    showToast(isTrackingHeading ? "Heading lock on" : "North-up map")
                } label: {
                    Image(systemName: isTrackingHeading ? "location.north.fill" : "location")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isTrackingHeading ? .blue : .white)
                        .padding(12)
                }
                .glassEffect(in: .circle)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                
                Button {
                    NotificationCenter.default.post(name: .recenterMap, object: nil)
                    showToast("Recentered")
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .glassEffect(in: .circle)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                
                Button {
                    toggleTrailMode()
                } label: {
                    Image(systemName: isTrailModeEnabled ? "point.topleft.filled.down.to.point.bottomright.curvepath" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isTrailModeEnabled ? .mint : .white)
                        .padding(12)
                }
                .glassEffect(in: .circle)
                .opacity(activeTrailLocations.isEmpty ? 0.45 : 1)
                .disabled(activeTrailLocations.isEmpty)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(.bottom, 0)
            .padding(.trailing, 160)
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.3), value: isSnappedToMap)
        }
    }
    
    @ViewBuilder
    private var modeToastOverlay: some View {
        if showModeToast {
            Text(modeToastText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 92)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    private func proximityColor(distance: Double) -> Color {
        switch distance {
        case 0..<15:    return .green
        case 15..<50:   return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 50..<100:  return .yellow
        case 100..<200: return .orange
        default:        return .red
        }
    }
    
    private func proximityLabel(distance: Double) -> String {
        switch distance {
        case 0..<5:     return "You're right there!"
        case 5..<15:    return "Very close"
        case 15..<50:   return "Getting closer"
        case 50..<100:  return "Nearby"
        case 100..<300: return "Keep walking"
        default:        return "Far away"
        }
    }
    
    private var trailStatusPill: some View {
        Label {
            Text("Trail \(Int(breadcrumbManager.trackedDistance))m")
        } icon: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private func navigationTarget(for currentLocation: CLLocation) -> CLLocation {
        guard isTrailModeEnabled, !activeTrailLocations.isEmpty else {
            return memory.location
        }
        
        if let trailWaypointIndex {
            return activeTrailLocations[trailWaypointIndex]
        }
        return memory.location
    }
    
    private func updateTrailProgress(with currentLocation: CLLocation) {
        guard isTrailModeEnabled, !activeTrailLocations.isEmpty else { return }
        
        if trailWaypointIndex == nil {
            let nearestIndex = nearestBreadcrumbIndex(to: currentLocation)
            trailWaypointIndex = nearestIndex
        }
        
        guard let currentIndex = trailWaypointIndex else { return }
        let target = activeTrailLocations[currentIndex]
        let distanceToTarget = currentLocation.distance(from: target)
        
        // When user reaches a waypoint, move toward earlier breadcrumbs (back to capture).
        if distanceToTarget <= 8 {
            if currentIndex > 0 {
                trailWaypointIndex = currentIndex - 1
            } else {
                trailWaypointIndex = nil
                isTrailModeEnabled = false
            }
        }
    }
    
    private func nearestBreadcrumbIndex(to location: CLLocation) -> Int {
        activeTrailLocations.enumerated().min { lhs, rhs in
            lhs.element.distance(from: location) < rhs.element.distance(from: location)
        }?.offset ?? 0
    }
    
    private func toggleTrailMode() {
        guard !activeTrailLocations.isEmpty else { return }
        isTrailModeEnabled.toggle()
        showToast(isTrailModeEnabled ? "Trail guidance on" : "Direct guidance on")
    }
    
    private func handleSnapDrag(_ value: DragGesture.Value, proxy: ScrollViewProxy) {
        let vertical = value.translation.height
        if vertical < -100 && !isSnappedToMap {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                proxy.scrollTo("map", anchor: .top)
                isSnappedToMap = true
            }
        } else if vertical > 200 && isSnappedToMap {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                proxy.scrollTo("top", anchor: .top)
                isSnappedToMap = false
            }
        }
    }
    
    private func toggleSnapState(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            if isSnappedToMap {
                proxy.scrollTo("top", anchor: .top)
                isSnappedToMap = false
            } else {
                proxy.scrollTo("map", anchor: .top)
                isSnappedToMap = true
            }
        }
    }
    
    private func handleAppear() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        lastNavigationMode = navigationStateManager.currentMode
    }
    
    private func handleTrailModeChange(_ isEnabled: Bool) {
        if !isEnabled {
            trailWaypointIndex = nil
        }
    }
    
    private func handleLocationChange(_ location: CLLocation?) {
        guard let location else { return }
        confidenceManager.ingest(location)
        navigationStateManager.updateMode(from: confidenceManager.currentConfidence)
        let mode = navigationStateManager.currentMode
        if mode != lastNavigationMode {
            if shouldShowModeToast(from: lastNavigationMode, to: mode) {
                showToast(modeToastText(for: mode))
                lastModeToastAt = Date()
            }
            lastNavigationMode = mode
        }
        _ = effectiveCurrentLocation(from: location)
    }
    
    private func handleDisappear() {
        locationManager.stopUpdating()
        directionalGuidanceManager.deactivate()
        HapticDirectionManager.shared.stop()
    }
    
    private var activeTrailLocations: [CLLocation] {
        // Refined trail is only trusted when origin refinement was committed.
        if memory.refinementMode == "committed", memory.hasRefinedTrail {
            return memory.refinedTrailCoordinates.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        return memory.breadcrumbs.map(\.location)
    }
    
    @discardableResult
    private func effectiveCurrentLocation(from rawLocation: CLLocation) -> CLLocation? {
        let mode = navigationStateManager.currentMode

        if mode == .gpsUnreliable {
            if !directionalGuidanceManager.isActive {
                directionalGuidanceManager.activate(anchor: rawLocation)
            }
            let heading = resolvedHeading(for: rawLocation)
            directionalGuidanceManager.update(
                estimatedLocation: rawLocation,
                headingDegrees: heading,
                targetLocation: navigationTarget(for: rawLocation)
            )
        } else {
            directionalGuidanceManager.deactivate()
        }
        updateTrailProgress(with: rawLocation)
        return rawLocation
    }
    
    private func resolvedHeading(for location: CLLocation) -> Double {
        if let heading = locationManager.currentHeading {
            if heading.trueHeading >= 0 { return heading.trueHeading }
            if heading.magneticHeading >= 0 { return heading.magneticHeading }
        }
        if location.course >= 0 { return location.course }
        return memory.heading
    }
    
    private func shouldShowModeToast(from oldMode: NavigationMode, to newMode: NavigationMode) -> Bool {
        // Only toast major transitions to avoid noisy UI during signal fluctuation.
        guard oldMode == .gpsUnreliable || newMode == .gpsUnreliable else {
            return false
        }
        return Date().timeIntervalSince(lastModeToastAt) >= modeToastCooldown
    }
    
    private func modeToastText(for mode: NavigationMode) -> String {
        switch mode {
        case .gpsReliable:
            return "Strong GPS, using Precise Mode"
        case .gpsDegrading:
            return "GPS Degrading, using Trail Mode"
        case .gpsUnreliable:
            return "Weak Signal, Guiding by Direction"
        }
    }
    
    private func showToast(_ text: String) {
        modeToastText = text
        withAnimation {
            showModeToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation {
                showModeToast = false
            }
        }
    }
    
}

// MARK: - Tracker View (isolated — heading updates only re-render this)
struct TrackerView: View {
    let distance: Double
    let rotationAngle: Double
    
    @State private var smoothedAngle: Double = 0
    @State private var arrowScale: Double = 1.0
    @State private var isMagneticallyLocked = false
    
    private var color: Color {
        switch distance {
        case 0..<15:    return .green
        case 15..<50:   return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 50..<100:  return .yellow
        case 100..<200: return .orange
        default:        return .red
        }
    }
    
    private var radarSpeed: Double {
        switch distance {
        case 0..<15:   return 0.8
        case 15..<50:  return 1.2
        case 50..<100: return 1.6
        default:       return 2.2
        }
    }
    
    private var dynamicColor: Color {
        let normalizedAngle = {
            var angle = rotationAngle
            while angle > 180  { angle -= 360 }
            while angle < -180 { angle += 360 }
            return angle
        }()

        let absAngle = abs(normalizedAngle)
        let alignment = max(0, (180 - absAngle) / 180)
        
        return color.opacity(0.6 + (alignment * 0.8))
    }
    
    private var brightnessAmount: Double {
        let normalizedAngle = {
            var angle = rotationAngle
            while angle > 180  { angle -= 360 }
            while angle < -180 { angle += 360 }
            return angle
        }()

        let absAngle = abs(normalizedAngle)
        let alignment = max(0, (180 - absAngle) / 180)
        
        return alignment * 0.1
    }
    
    var body: some View {
        ZStack {
            PulseRing(color: color, pulseSpeed: radarSpeed)
            
            // Main circle
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 120, height: 120)
            
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 120, height: 120)
            
            Circle()
                .stroke(Color.white.opacity(isMagneticallyLocked ? 0.45 : 0), lineWidth: 3)
                .frame(width: 132, height: 132)
                .scaleEffect(isMagneticallyLocked ? 1.04 : 0.97)
                .blur(radius: isMagneticallyLocked ? 0 : 2)
                .animation(.easeInOut(duration: 0.22), value: isMagneticallyLocked)
            
            // Arrow
            Image(systemName: "arrow.up")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(dynamicColor)
                .brightness(brightnessAmount)
                .rotationEffect(.degrees(smoothedAngle))
                .scaleEffect(arrowScale)
                .animation(.easeInOut(duration: 0.3), value: smoothedAngle)
        }
        .onChange(of: rotationAngle) { _, newAngle in
            var delta = newAngle - smoothedAngle
            while delta > 180  { delta -= 360 }
            while delta < -180 { delta += 360 }
            smoothedAngle += delta
            
            let absAngle = min(abs(newAngle), 180)
            let alignment = max(0, (180 - absAngle) / 180)
            
            let targetScale = 1.0 + (alignment * 0.15)
            
            withAnimation(.easeOut(duration: 0.2)) {
                arrowScale = targetScale
            }
            
            let nowLocked = abs(newAngle) <= 7
            if nowLocked != isMagneticallyLocked {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMagneticallyLocked = nowLocked
                }
            }
        }
    }
}

// MARK: - Pulse Ring
struct PulseRing: View {
    let color: Color
    let pulseSpeed: Double
    
    @State private var animate = false
    
    var body: some View {
        Circle()
            .stroke(color.opacity(animate ? 0 : 0.45), lineWidth: 1.5)
            .frame(width: animate ? 230 : 120, height: animate ? 230 : 120)
            .animation(
                .linear(duration: pulseSpeed)
                .repeatForever(autoreverses: false),
                value: animate
            )
            .onAppear { restartPulse() }
            .onChange(of: pulseSpeed) { _, _ in restartPulse() }
    }
    
    private func restartPulse() {
        animate = false
        DispatchQueue.main.async {
            animate = true
        }
    }
}

// MARK: - Breadcrumb Map
struct BreadcrumbMapView: UIViewRepresentable {
    let memory: MemoryNode
    let currentLocation: CLLocation
    let isSnappedToMap: Bool
    let isTrackingHeading: Bool
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.layer.borderWidth = 1
        mapView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        context.coordinator.mapView = mapView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.recenter),
            name: .recenterMap,
            object: nil
        )
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update tracking mode
        if isSnappedToMap {
            if isTrackingHeading {
                mapView.userTrackingMode = .followWithHeading
            } else {
                mapView.userTrackingMode = .none
                let camera = MKMapCamera(
                    lookingAtCenter: mapView.centerCoordinate,
                    fromDistance: mapView.camera.altitude,
                    pitch: 0,
                    heading: 0
                )
                mapView.setCamera(camera, animated: true)
            }
        } else {
            mapView.userTrackingMode = .none
        }
        
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        
        let capturePin = MKPointAnnotation()
        capturePin.coordinate = targetCoordinate
        capturePin.title = memory.hasRefinedLocation ? "Refined capture location" : "Captured here"
        mapView.addAnnotation(capturePin)
        
        var coords: [CLLocationCoordinate2D] = []
        coords.append(targetCoordinate)
        let trailCoords = memory.hasRefinedTrail
            ? memory.refinedTrailCoordinates
            : memory.breadcrumbs.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        coords.append(contentsOf: trailCoords)
        if coords.count > 1 {
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline)
        }
        
        // Re-center when snap state changes
        if context.coordinator.lastSnappedState != isSnappedToMap {
            context.coordinator.lastSnappedState = isSnappedToMap
            var allCoords = coords
            allCoords.append(currentLocation.coordinate)
            let region = regionForCoordinates(allCoords)
            mapView.setRegion(region, animated: true)
        } else if !context.coordinator.hasSetRegion {
            context.coordinator.hasSetRegion = true
            var allCoords = coords
            allCoords.append(currentLocation.coordinate)
            mapView.setRegion(regionForCoordinates(allCoords), animated: false)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var hasSetRegion = false
        var lastSnappedState: Bool = false
        weak var mapView: MKMapView?
        
        @objc func recenter() {
            guard let mapView else { return }
            mapView.userTrackingMode = .none
            let camera = MKMapCamera(
                lookingAtCenter: mapView.centerCoordinate,
                fromDistance: mapView.camera.altitude * 2,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: true)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7)
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "capture")
            view.markerTintColor = .systemGreen
            view.glyphImage = UIImage(systemName: "camera.fill")
            return view
        }
    }
    
    private func regionForCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: targetCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        }
        let minLat = coordinates.map(\.latitude).min()!
        let maxLat = coordinates.map(\.latitude).max()!
        let minLon = coordinates.map(\.longitude).min()!
        let maxLon = coordinates.map(\.longitude).max()!
        
        let latDelta = isSnappedToMap
            ? max((maxLat - minLat) * 1.25, 0.0045)
            : max((maxLat - minLat) * 1.35, 0.0058)

        let lonDelta = isSnappedToMap
            ? max((maxLon - minLon) * 1.25, 0.0045)
            : max((maxLon - minLon) * 1.35, 0.0058)
        
        let centerLat = isSnappedToMap
            ? (minLat + maxLat) / 2
            : (minLat + maxLat) / 2 + latDelta * -0.25
        
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
    
    private var targetCoordinate: CLLocationCoordinate2D {
        memory.location.coordinate
    }
}
// MARK: - Haptic Direction Manager
class HapticDirectionManager {
    static let shared = HapticDirectionManager()
    
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let softSelection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    private var lastHapticTime: Date = .distantPast
    private var wasInPeakZone = false
    private var wasInRange = false
    private var wasMagneticallyLocked = false
    private var smoothedIntensity: Double = 0.45
    
    private let maxDistance: Double = 120
    private let angleRange: Double = 120
    private let peakAngle: Double = 10
    private let magneticLockAngle: Double = 7
    
    init() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        softSelection.prepare()
        notification.prepare()
    }
    
    func update(angleDiff: Double, distance: Double) {
        guard distance <= maxDistance else {
            wasInRange = false
            wasInPeakZone = false
            return
        }
        
        let absAngle = min(abs(angleDiff), 180)
        guard absAngle < angleRange else {
            wasInRange = false
            wasInPeakZone = false
            wasMagneticallyLocked = false
            return
        }
        
        wasInRange = true
        let nowMagneticallyLocked = absAngle <= magneticLockAngle
        if nowMagneticallyLocked && !wasMagneticallyLocked {
            softSelection.selectionChanged()
        }
        wasMagneticallyLocked = nowMagneticallyLocked
        let inPeakZone = absAngle <= peakAngle
        let now = Date()
        
        if inPeakZone && !wasInPeakZone {
            wasInPeakZone = true
            notification.notificationOccurred(.success)
            // Entry cue only once; sustained cadence below is distance-tempo synced.
            let entryIntensity = CGFloat(min(0.8, max(0.22, distanceIntensityFactor(distance: distance))))
            if distance > 85 {
                light.impactOccurred(intensity: entryIntensity * 0.65)
            } else if distance > 35 {
                medium.impactOccurred(intensity: entryIntensity * 0.8)
            } else {
                heavy.impactOccurred(intensity: entryIntensity)
            }
            lastHapticTime = Date()
            return
        }
        
        if !inPeakZone { wasInPeakZone = false }

        let interval = inPeakZone
            ? ringPulseInterval(distance: distance)
            : pulseInterval(angleDiff: angleDiff)
        guard now.timeIntervalSince(lastHapticTime) >= interval else { return }
        lastHapticTime = now
        
        let a = alignment(for: absAngle)
        let angleIntensity = 0.35 + (a * 0.65)
        let distanceIntensity = distanceIntensityFactor(distance: distance)
        let rawIntensity = angleIntensity * distanceIntensity
        smoothedIntensity = (smoothedIntensity * 0.7) + (rawIntensity * 0.3)
        let intensity = CGFloat(smoothedIntensity)
        
        if inPeakZone {
            // Match pulse ring tempo while keeping far-distance haptics subtle.
            if distance > 85 {
                light.impactOccurred(intensity: max(0.12, intensity * 0.5))
            } else if distance > 35 {
                medium.impactOccurred(intensity: max(0.16, intensity * 0.72))
            } else {
                heavy.impactOccurred(intensity: max(0.22, intensity))
            }
        } else {
            if absAngle < 30      { heavy.impactOccurred(intensity: intensity) }
            else if absAngle < 60 { medium.impactOccurred(intensity: intensity) }
            else                  { light.impactOccurred(intensity: intensity * 0.7) }
        }
    }
    
    func alignment(for absAngle: Double) -> Double {
        (angleRange - min(absAngle, angleRange)) / angleRange
    }
    
    func pulseInterval(angleDiff: Double) -> Double {
        let absAngle = min(abs(angleDiff), 180)
        guard absAngle < angleRange else { return 2.5 }
        let a = alignment(for: absAngle)
        return 2.5 - ((a * a) * 2.35)
    }

    // Keep peak-direction haptic cadence aligned with TrackerView's pulse ring speed.
    private func ringPulseInterval(distance: Double) -> Double {
        switch distance {
        case 0..<15:   return 0.8
        case 15..<50:  return 1.2
        case 50..<100: return 1.6
        default:       return 2.2
        }
    }
    
    private func distanceIntensityFactor(distance: Double) -> Double {
        // Close = strong directional cues, far = subtle guidance.
        let normalized = max(0, min(1, distance / maxDistance))
        return max(0.2, 1.0 - (normalized * 0.75))
    }
    
    func stop() {
        wasInRange = false
        wasInPeakZone = false
        wasMagneticallyLocked = false
    }
}
extension Notification.Name {
    static let recenterMap = Notification.Name("recenterMap")
}
