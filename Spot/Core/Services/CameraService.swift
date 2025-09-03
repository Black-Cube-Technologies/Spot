// CameraService.swift

import AVFoundation
import Combine

final class CameraService: NSObject,
                           CameraStreaming,
                           AVCaptureDataOutputSynchronizerDelegate,
                           AVCaptureDepthDataOutputDelegate,
                           AVCaptureVideoDataOutputSampleBufferDelegate {

    // Updated: make it public if your protocol is public across modules
    public let session = AVCaptureSession() // Updated

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue   = DispatchQueue(label: "camera.video.queue")

    private let videoOutput  = AVCaptureVideoDataOutput()
    private let depthOutput  = AVCaptureDepthDataOutput()     // Added
    private var synchronizer: AVCaptureDataOutputSynchronizer?// Added

    private let packSubject  = PassthroughSubject<FramePack, Never>() // Updated
    public var frames: AnyPublisher<FramePack, Never> {                // Updated
        packSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            // Prefer depth-capable back camera
            let device =
                //AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            guard let videoDevice = device,
                  let input = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration(); return
            }
            self.session.addInput(input)
            self.configureNearContinuousFocus(videoDevice, roi: CGPoint(x: 0.5, y: 0.5))

            // Video
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration(); return
            }
            self.session.addOutput(self.videoOutput)

            if let c = self.videoOutput.connection(with: .video) {
                if c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }
                if c.isVideoStabilizationSupported { c.preferredVideoStabilizationMode = .standard }
                //if #available(iOS 17.0, *) { c.videoRotationAngle = 90 } else { c.videoOrientation = .portrait }
            }

            // Depth (try; fall back to RGB-only if not supported)
            if self.session.canAddOutput(self.depthOutput) {
                self.session.addOutput(self.depthOutput)
                self.depthOutput.isFilteringEnabled = true
                self.depthOutput.setDelegate(self, callbackQueue: self.videoQueue)

                if let depthConn = self.depthOutput.connection(with: .depthData), depthConn.isEnabled {
                    self.synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                    self.synchronizer?.setDelegate(self, queue: self.videoQueue)
                } else {
                    self.session.removeOutput(self.depthOutput)
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                }
            } else {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { guard !self.session.isRunning else { return }; self.session.startRunning() }
    }
    func stop()  {
        sessionQueue.async { guard  self.session.isRunning else { return }; self.session.stopRunning()  }
    }
    
    private func configureNearContinuousFocus(_ device: AVCaptureDevice,
                                              roi: CGPoint? = nil,       // normalized [0,1] (0,0 top-left)
                                              targetZoom: CGFloat? = 2.0 // small zoom helps close focus
    ) {
        do {
            try device.lockForConfiguration()
            
            // Prefer near range to bias autofocus for close-ups (macro-like)
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            
            // Smooth AF avoids visible pulsing while hunting
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            
            // Continuous AF/AE/AWB
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            // Small ROI (center by default). Use your detection box to update this later.
            if let p = roi {
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = p }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = p }
            }
            
            // Let camera refocus when the subject moves
            device.isSubjectAreaChangeMonitoringEnabled = true
            
            // A little zoom helps the phone reach its minimum focus distance and fill the frame
            if let z = targetZoom {
                let clamped = min(max(z, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if abs(device.videoZoomFactor - clamped) > 0.01 {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
                }
            }
            
            // Optional: gentle torch to stabilize AF in low light
            if device.hasTorch && device.isTorchModeSupported(.on) {
                try? device.setTorchModeOn(level: 0.15) // low fill to reduce noise/hunting
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Focus config failed: \(error)")
        }
    }

    // MARK: Synchronizer → RGB + optional Depth
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped else { return }
        let sb = syncedVideo.sampleBuffer

        var depth: AVDepthData?
        if let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput)
            as? AVCaptureSynchronizedDepthData,
           !syncedDepth.depthDataWasDropped {
            depth = syncedDepth.depthData
        }
        packSubject.send(FramePack(sampleBuffer: sb, depthData: depth)) // Updated
    }

    // MARK: Fallback when no synchronizer (RGB only)
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        packSubject.send(FramePack(sampleBuffer: sampleBuffer, depthData: nil)) // Updated
    }
}
