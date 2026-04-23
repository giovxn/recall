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
            Color.black
                .ignoresSafeArea()

            CameraPreview(camera: camera)
                .ignoresSafeArea(edges: [.top, .horizontal])
                .scaleEffect(0.95)
                .offset(y: -4)
                .padding(.bottom, 58)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.22),
                            .black.opacity(0.52),
                            .black.opacity(0.82),
                            .black.opacity(0.95),
                            .black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 170)
                }
            
            VStack {
                Spacer()

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.26), radius: 18, y: 6)
                        .frame(height: 80)
                        .padding(.horizontal, 68)

                    HStack {
                        Button {
                        } label: {
                            Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(camera.isTorchOn ? .yellow : .white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .disabled(!camera.supportsFlash)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in
                                    camera.toggleFlashFromLongPress()
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                        )

                        Spacer()
                        Button {
                            camera.toggleWideZoom()
                        } label: {
                            Image(systemName: camera.isWideZoomMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                    }
                    .padding(.horizontal, 90)
                    .padding(.top, 22)

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
                    .offset(y: -8)
                }
                .padding(.bottom, 6)
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
            memory.refinementMode = locationManager.isGoodCaptureFix(location) ? "none" : "pending"
            
            modelContext.insert(memory)
            try? modelContext.save()
            
            // Run Vision analysis in background
            VisionAnalyzer.shared.analyze(imageData: imageData) { analysis in
                memory.classification = analysis.classification
                memory.smartLabel = analysis.smartLabel
                memory.detectedText = analysis.detectedText
                memory.dominantColorHex = analysis.dominantColor.toHex()
                try? self.modelContext.save()
            }
            
            BreadcrumbManager.shared.start(for: memory, context: modelContext)
            LiveActivityManager.shared.startActivity(memory: memory)
            refinePendingLocation(for: memory, initialLocation: location)
            
            withAnimation {
                showSavedFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showSavedFeedback = false }
            }
        }
    }

    private func refinePendingLocation(for memory: MemoryNode, initialLocation: CLLocation) {
        locationManager.refineCaptureLocation(initialLocation: initialLocation, timeout: 8) { refinedLocation, isHighConfidence in
            memory.refinedLatitude = refinedLocation.coordinate.latitude
            memory.refinedLongitude = refinedLocation.coordinate.longitude
            memory.gpsRecoveredAt = Date()
            memory.gpsRecoveredLatitude = refinedLocation.coordinate.latitude
            memory.gpsRecoveredLongitude = refinedLocation.coordinate.longitude
            memory.refinementMode = isHighConfidence ? "committed" : "fallback"
            try? modelContext.save()
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
        let view = PreviewContainerView()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.videoGravity = videoGravity

        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        context.coordinator.camera = camera
        context.coordinator.containerView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewView = uiView as? PreviewContainerView {
            previewView.previewLayer?.videoGravity = videoGravity
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        weak var camera: CameraManager?
        weak var containerView: PreviewContainerView?
        private var pinchStartZoom: CGFloat = 1.0
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewContainerView else { return }
            let point = recognizer.location(in: view)
            camera?.focus(at: point, previewLayer: previewLayer)
            view.showFocusIndicator(at: point)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let camera else { return }
            switch recognizer.state {
            case .began:
                pinchStartZoom = camera.zoomFactor
            case .changed:
                camera.setZoom(factor: pinchStartZoom * recognizer.scale)
            default:
                break
            }
        }
    }
}

final class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func showFocusIndicator(at point: CGPoint) {
        let size: CGFloat = 80
        let indicator = UIView(frame: CGRect(
            x: point.x - (size / 2),
            y: point.y - (size / 2),
            width: size,
            height: size
        ))
        indicator.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        indicator.layer.borderWidth = 1.5
        indicator.layer.cornerRadius = 12
        indicator.backgroundColor = .clear
        indicator.alpha = 0
        
        addSubview(indicator)
        
        UIView.animate(withDuration: 0.15, animations: {
            indicator.alpha = 1
            indicator.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0.45, options: [.curveEaseOut], animations: {
                indicator.alpha = 0
            }, completion: { _ in
                indicator.removeFromSuperview()
            })
        }
    }
}
