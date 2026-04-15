//
//  CaptureView.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import SwiftUI
import AVFoundation
import SwiftData
import CoreLocation
import UIKit

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager = LocationManager()
    @StateObject private var camera = CameraManager()
    
    @State private var showSavedFeedback = false
    
    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button {
                    capture()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 80, height: 80)
                        Circle()
                            .stroke(.white.opacity(0.4), lineWidth: 4)
                            .frame(width: 94, height: 94)
                    }
                }
                .padding(.bottom, 40)
            }
            
            if showSavedFeedback {
                VStack {
                    Spacer()
                    Text("Saved")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.bottom, 160)
                }
                .transition(.opacity)
            }
            
            if camera.authorizationStatus != .authorized {
                cameraPermissionOverlay
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()
            camera.requestAccessIfNeeded()
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }
    
    private func capture() {
        camera.capturePhoto { imageData in
            guard let imageData,
                  let location = locationManager.bestRecentLocation() ?? locationManager.currentLocation else { return }
            
            let heading = locationManager.currentHeading?.trueHeading ?? 0
            
            let memory = MemoryNode(
                imageData: imageData,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                heading: heading,
                captureHorizontalAccuracy: max(location.horizontalAccuracy, 0)
            )
            memory.captureAltitude = location.altitude
            memory.captureVerticalAccuracy = location.verticalAccuracy > 0 ? location.verticalAccuracy : nil
            
            modelContext.insert(memory)
            
            // Run Vision analysis in background
            VisionAnalyzer.shared.analyze(imageData: imageData) { analysis in
                memory.classification = analysis.classification
                memory.smartLabel = analysis.smartLabel
                memory.detectedText = analysis.detectedText
                memory.dominantColorHex = analysis.dominantColor.toHex()
                try? self.modelContext.save()
            }
            
            BreadcrumbManager.shared.start(for: memory, context: modelContext)
            LiveActivityManager.shared.startActivity(memory: memory, arrow: "↑", distance: "Calculating...")
            
            withAnimation {
                showSavedFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showSavedFeedback = false }
            }
        }
    }
    
    @ViewBuilder
    private var cameraPermissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
            Text(cameraPermissionMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if camera.authorizationStatus == .denied || camera.authorizationStatus == .restricted {
                Button("open settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(22)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var cameraPermissionMessage: String {
        switch camera.authorizationStatus {
        case .notDetermined:
            return "Requesting camera access..."
        case .denied, .restricted:
            return "Camera access is off. Enable it in Settings to capture memories."
        case .authorized:
            return ""
        @unknown default:
            return "Camera unavailable."
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraManager
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = videoGravity
        previewLayer.frame = view.bounds

        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
