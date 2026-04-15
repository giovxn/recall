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
    private var photoContinuation: ((Data?) -> Void)?
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isSessionConfigured = false
    
    override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    private func setupSession() {
        guard !isSessionConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInUltraWideCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: .back
        )
        
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        
        session.commitConfiguration()
        isSessionConfigured = true
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
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async {
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
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoContinuation?(photo.fileDataRepresentation())
        photoContinuation = nil
    }
}
