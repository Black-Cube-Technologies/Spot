// CameraService.swift

import AVFoundation
import Combine

final class CameraService: NSObject,
                           CameraZoomControlling,
                           CameraStreaming,
                           AVCaptureDataOutputSynchronizerDelegate,
                           AVCaptureDepthDataOutputDelegate,
                           AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    // Updated: make it public if your protocol is public across modules
    public let session = AVCaptureSession() // Updated
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue   = DispatchQueue(label: "camera.video.queue")
    
    private var cameraDevice: AVCaptureDevice?
    
    private let videoOutput  = AVCaptureVideoDataOutput()
    private let depthOutput  = AVCaptureDepthDataOutput()     // Added
    private var synchronizer: AVCaptureDataOutputSynchronizer?// Added
    
    private let packSubject  = PassthroughSubject<FramePack, Never>() // Updated
    public var frames: AnyPublisher<FramePack, Never> {                // Updated
        packSubject.eraseToAnyPublisher()
    }
    
    private let zoomSubject = CurrentValueSubject<CGFloat, Never>(1.0)
    public var currentZoom: AnyPublisher<CGFloat, Never> { zoomSubject.eraseToAnyPublisher() }
    
    public private(set) var minZoomFactor: CGFloat = 1.0
    public private(set) var maxZoomFactor: CGFloat = 5.0
    public private(set) var switchOverFactors: [CGFloat] = [1.0, 5.0]
    
    
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
            
            self.cameraDevice = videoDevice
            
            self.session.addInput(input)
            //self.configureNearContinuousFocus(videoDevice, roi: CGPoint(x: 0.5, y: 0.5))
            
            // Video
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA]
            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration(); return
            }
            self.session.addOutput(self.videoOutput)
            
            if let c = self.videoOutput.connection(with: .video) {
                if c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }
                if #available(iOS 17.0, *) { c.videoRotationAngle = 90 } else { c.videoOrientation = .portrait }
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
    
    public func setZoom(_ factor: CGFloat, animated: Bool = true, rate: Float = 8.0) {
        sessionQueue.async {
            self._setZoomUnsafe(factor, animated: animated, rate: rate)
        }
    }
    
    public func cancelZoomRamp() {
        sessionQueue.async {
            guard let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    private func _setZoomUnsafe(_ f: CGFloat, animated: Bool, rate: Float) {
        guard let device = self.cameraDevice else { return }
        let clamped = max(self.minZoomFactor, min(f, self.maxZoomFactor))
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clamped, withRate: rate)
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
            self.zoomSubject.send(clamped)
        } catch {
            // Ignore (device might be changing formats)
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
    
    func getCameraDevice() -> AVCaptureDevice?{
        return self.cameraDevice
    }
    
    
}
