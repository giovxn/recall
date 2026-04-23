//
//  CameraManager.swift
//  Recall
//
//  Created by Giovanni Icasiano on 03/04/2026.
//

import AVFoundation
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "recall.camera.session", qos: .userInitiated)
    private var photoContinuation: ((Data?) -> Void)?
    private var activeDevice: AVCaptureDevice?
    private var lastStandardZoomFactor: CGFloat = 1.0
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var isWideZoomMode: Bool = false
    @Published private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    @Published private(set) var isTorchOn: Bool = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isSessionConfigured = false
    
    override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    private func setupSession() {
        guard !isSessionConfigured else { return }
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            
            let preferredTypes: [AVCaptureDevice.DeviceType] = [
                .builtInDualWideCamera,
                .builtInWideAngleCamera,
                .builtInUltraWideCamera
            ]
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: preferredTypes,
                mediaType: .video,
                position: .back
            )
            
            guard let device = discovery.devices.first,
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }
            
            self.activeDevice = device
            self.configureDevice(device)
            
            if self.session.canAddInput(input) { self.session.addInput(input) }
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            
            self.output.maxPhotoQualityPrioritization = .quality
            if #available(iOS 16.0, *) {
                let supported = device.activeFormat.supportedMaxPhotoDimensions
                if let best = self.bestPhotoDimensions(from: supported) {
                    self.output.maxPhotoDimensions = best
                }
            }
            
            let connection = self.output.connection(with: .video)
            if connection?.isVideoStabilizationSupported == true {
                connection?.preferredVideoStabilizationMode = .auto
            }
            
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.isSessionConfigured = true
            }
        }
    }
    
    func requestAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status
        
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.setupSession()
                        self?.startSession()
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }
    
    func startSession() {
        guard authorizationStatus == .authorized else { return }
        if !isSessionConfigured {
            setupSession()
        }
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if let device = self.activeDevice, device.hasTorch, device.torchMode == .on {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {}
                DispatchQueue.main.async {
                    self.isTorchOn = false
                    self.flashMode = .off
                }
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func capturePhoto(completion: @escaping (Data?) -> Void) {
        guard authorizationStatus == .authorized else {
            completion(nil)
            return
        }
        photoContinuation = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        settings.flashMode = (supportsFlash ? flashMode : .off)
        if #available(iOS 16.0, *) {
            if let device = activeDevice {
                let supported = device.activeFormat.supportedMaxPhotoDimensions
                if let best = bestPhotoDimensions(from: supported) {
                settings.maxPhotoDimensions = best
                }
            }
        }
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoContinuation?(photo.fileDataRepresentation())
        photoContinuation = nil
    }

    func focus(at pointInPreview: CGPoint, previewLayer: AVCaptureVideoPreviewLayer?) {
        guard let device = activeDevice else { return }
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: pointInPreview)
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    func setZoom(factor: CGFloat, animated: Bool = false) {
        guard let device = activeDevice else { return }
        sessionQueue.async {
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 6.0)
            let clamped = max(minZoom, min(factor, maxZoom))
            do {
                try device.lockForConfiguration()
                if animated {
                    if device.isRampingVideoZoom {
                        device.cancelVideoZoomRamp()
                    }
                    // Ramp gives a much smoother camera-like zoom transition.
                    device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
                } else {
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.zoomFactor = clamped
                    if !self.isWideZoomMode && clamped >= 0.8 {
                        self.lastStandardZoomFactor = clamped
                    }
                }
            } catch {
                return
            }
        }
    }

    func zoomBounds() -> (min: CGFloat, max: CGFloat) {
        guard let device = activeDevice else { return (1.0, 6.0) }
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 6.0)
        return (minZoom, maxZoom)
    }

    func cycleZoomPreset() {
        let sequence: [CGFloat] = [1.0, 2.0, 0.5]
        let current = zoomFactor
        let nearestIndex = sequence.enumerated().min {
            abs($0.element - current) < abs($1.element - current)
        }?.offset ?? 0
        let next = sequence[(nearestIndex + 1) % sequence.count]
        setZoom(factor: next)
    }

    func toggleWideZoom() {
        let targetZoom: CGFloat
        if isWideZoomMode {
            targetZoom = lastStandardZoomFactor
        } else {
            if zoomFactor >= 0.8 {
                lastStandardZoomFactor = zoomFactor
            }
            guard let device = activeDevice else {
                targetZoom = 0.5
                setZoom(factor: targetZoom, animated: true)
                return
            }
            targetZoom = max(device.minAvailableVideoZoomFactor, 0.5)
        }
        isWideZoomMode.toggle()
        setZoom(factor: targetZoom, animated: true)
    }

    var supportsFlash: Bool {
        activeDevice?.hasFlash == true || activeDevice?.hasTorch == true
    }

    func cycleFlashMode() {
        guard supportsFlash else { return }
        switch flashMode {
        case .off:
            flashMode = .auto
        case .auto:
            flashMode = .on
        case .on:
            flashMode = .off
        @unknown default:
            flashMode = .off
        }
    }

    func flashIconName() -> String {
        switch flashMode {
        case .off:
            return "bolt.slash.fill"
        case .auto:
            return "bolt.badge.a.fill"
        case .on:
            return "bolt.fill"
        @unknown default:
            return "bolt.slash.fill"
        }
    }

    func toggleFlashFromLongPress() {
        guard let device = activeDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.hasTorch {
                    let nextTorchState = !self.isTorchOn
                    if nextTorchState {
                        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                    } else {
                        device.torchMode = .off
                    }
                    DispatchQueue.main.async {
                        self.isTorchOn = nextTorchState
                        self.flashMode = nextTorchState ? .on : .off
                    }
                } else if device.hasFlash {
                    DispatchQueue.main.async {
                        self.flashMode = (self.flashMode == .on) ? .off : .on
                    }
                }
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 6.0)
            let defaultZoom = preferredDefaultZoom(for: device, minZoom: minZoom, maxZoom: maxZoom)
            device.videoZoomFactor = defaultZoom
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.zoomFactor = defaultZoom
                self.lastStandardZoomFactor = defaultZoom
                self.isWideZoomMode = false
            }
        } catch {
            return
        }
    }

    @available(iOS 16.0, *)
    private func bestPhotoDimensions(from dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        dimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    private func preferredDefaultZoom(for device: AVCaptureDevice, minZoom: CGFloat, maxZoom: CGFloat) -> CGFloat {
        var defaultZoom: CGFloat = 1.0
        if device.deviceType == .builtInDualWideCamera {
            // On dual-wide virtual camera, the first switch-over factor is usually "wide 1x".
            if let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                defaultZoom = CGFloat(truncating: switchOver)
            }
        }
        return max(minZoom, min(defaultZoom, maxZoom))
    }
}
