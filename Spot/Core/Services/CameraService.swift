//
//  CameraService.swift
//  Spot
//
//  Created by Hasan on 18/08/2025.
//


import AVFoundation
import Combine

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue   = DispatchQueue(label: "camera.video.queue")
    private let videoOutput  = AVCaptureVideoDataOutput()

    // Emits frames for downstream detection
    let frameSubject = PassthroughSubject<CMSampleBuffer, Never>()

    func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            // Input
            guard let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back).devices.first,
                  let input = try? AVCaptureDeviceInput(device: videoDevice),
                    self.session.canAddInput(input) else{
                self.session.commitConfiguration();
                return
            }
            
            self.session.addInput(input)

            // Output
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA
            ]
            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration(); return
            }
            self.session.addOutput(self.videoOutput)
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)

            // iOS 17+: prefer rotationAngle; keep orientation fallback if needed
            if let c = self.videoOutput.connections.first {
                if #available(iOS 17.0, *) {
                    c.videoRotationAngle = 90 // portrait
                } else {
                    c.videoOrientation = .portrait
                }
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // running on videoQueue
        frameSubject.send(sampleBuffer)
    }
}
