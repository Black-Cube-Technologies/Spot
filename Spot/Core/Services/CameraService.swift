// CameraService.swift

import AVFoundation
import Combine
import CoreVideo
import CoreGraphics

final class CameraService: NSObject,
                           CameraZoomControlling,
                           CameraStreaming,
                           AVCaptureDataOutputSynchronizerDelegate,
                           AVCaptureDepthDataOutputDelegate,
                           AVCaptureVideoDataOutputSampleBufferDelegate {

    
    func getCameraDevice() -> AVCaptureDevice? {
        return cameraDevice
    }
    // MARK: - Session & outputs
    public let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue   = DispatchQueue(label: "camera.video.queue")

    private var cameraDevice: AVCaptureDevice?

    private let videoOutput  = AVCaptureVideoDataOutput()
    private let depthOutput  = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?

    // Frames publisher (unchanged)
    private let packSubject  = PassthroughSubject<FramePack, Never>()
    public var frames: AnyPublisher<FramePack, Never> { packSubject.eraseToAnyPublisher() }

    // Zoom publisher & API (unchanged)
    private let zoomSubject = CurrentValueSubject<CGFloat, Never>(1.0)
    public var currentZoom: AnyPublisher<CGFloat, Never> { zoomSubject.eraseToAnyPublisher() }

    public private(set) var minZoomFactor: CGFloat = 1.0
    public private(set) var maxZoomFactor: CGFloat = 10.0
    public private(set) var switchOverFactors: [CGFloat] = [1.0, 10.0]

    // MARK: - Brightness + torch (new gating)
    @Published public private(set) var brightness: CGFloat = 1.0   // 0.0 (dark) ... 1.0 (bright)

    /// Turn torch ON when brightness stays below this value for a short streak.
    public var torchOnThreshold: CGFloat = 0.22
    /// How many consecutive dark frames are required before turning torch ON.
    public var consecutiveDarkFramesForOn: Int = 6   // ~0.2s at 30fps
    /// Ignore auto-on decisions for this time after session starts (let AE settle).
    public var warmupDuration: TimeInterval = 0.6
    /// Torch power when turning ON
    public var torchLevel: Float = 0.75

    private var startAt: Date = .distantPast
    private var darkStreak: Int = 0

    override init() {
        super.init()
        configure()
    }

    // MARK: - Configure (720p, BGRA, depth sync preserved)
    private func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            let device =
                AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInDualCamera,     for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInWideAngleCamera,for: .video, position: .back)

            guard let videoDevice = device,
                  let input = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration(); return
            }

            self.cameraDevice = videoDevice
            self.session.addInput(input)

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            // Depth if available
            if self.session.canAddOutput(self.depthOutput) {
                self.session.addOutput(self.depthOutput)
                self.depthOutput.isFilteringEnabled = true
                self.depthOutput.setDelegate(self, callbackQueue: self.videoQueue)
            }

            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration(); return
            }
            self.session.addOutput(self.videoOutput)

            if let c = self.videoOutput.connection(with: .video) {
                if c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }
                if #available(iOS 17.0, *) { c.videoRotationAngle = 90 } else { c.videoOrientation = .portrait }
            }

            if self.depthOutput.connection(with: .depthData) != nil {
                self.synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                self.synchronizer?.setDelegate(self, queue: self.videoQueue)
            } else {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            }

            // Exposure prefs
            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoDevice.exposureMode = .continuousAutoExposure
                }
                if videoDevice.isLowLightBoostSupported {
                    videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
                videoDevice.unlockForConfiguration()
            } catch { /* ignore */ }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Start/Stop
    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.darkStreak = 0
            self.startAt = Date()
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.forceTorchOff()     // requirement: always close torch on stop
            self.session.stopRunning()
        }
    }

    // MARK: - Zoom controls (unchanged)
    public func setZoom(_ factor: CGFloat, animated: Bool = true, rate: Float = 8.0) {
        sessionQueue.async { self._setZoomUnsafe(factor, animated: animated, rate: rate) }
    }

    public func cancelZoomRamp() {
        sessionQueue.async {
            guard let device = self.cameraDevice else { return }
            do { try device.lockForConfiguration(); device.cancelVideoZoomRamp(); device.unlockForConfiguration() } catch { }
        }
    }

    private func _setZoomUnsafe(_ f: CGFloat, animated: Bool, rate: Float) {
        guard let device = self.cameraDevice else { return }
        let clamped = max(self.minZoomFactor, min(f, self.maxZoomFactor))
        do {
            try device.lockForConfiguration()
            if animated { device.ramp(toVideoZoomFactor: clamped, withRate: rate) }
            else { device.videoZoomFactor = clamped }
            device.unlockForConfiguration()
            self.zoomSubject.send(clamped)
        } catch { /* ignore */ }
    }

    // MARK: - Synced RGB(+Depth)
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped else { return }

        let sb = syncedVideo.sampleBuffer

        if let pb = CMSampleBufferGetImageBuffer(sb) {
            let b = computeNormalizedBrightness(from: pb)
            handleBrightness(b)
        }

        var depth: AVDepthData?
        if let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput)
            as? AVCaptureSynchronizedDepthData,
           !syncedDepth.depthDataWasDropped {
            depth = syncedDepth.depthData
        }

        packSubject.send(FramePack(sampleBuffer: sb, depthData: depth))
    }

    // MARK: - RGB-only fallback
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let b = computeNormalizedBrightness(from: pb)
            handleBrightness(b)
        }
        packSubject.send(FramePack(sampleBuffer: sampleBuffer, depthData: nil))
    }

    // MARK: - Brightness handling (startup warmup + dark streak)
    private func handleBrightness(_ b: CGFloat) {
        DispatchQueue.main.async { self.brightness = b }

        // Wait for warmup so AE can settle (prevents instant torch-on at launch)
        if Date().timeIntervalSince(startAt) < warmupDuration {
            darkStreak = 0
            return
        }

        if b < torchOnThreshold {
            darkStreak += 1
        } else {
            darkStreak = 0
        }

        if darkStreak >= consecutiveDarkFramesForOn {
            turnTorchOnIfPossible()
            darkStreak = 0 // prevent repeated attempts
        }
    }

    // MARK: - Torch helpers
    private func turnTorchOnIfPossible() {
        guard let d = cameraDevice, d.hasTorch else { return }
        guard d.torchMode != .on else { return }
        do {
            try d.lockForConfiguration()
            try d.setTorchModeOn(level: max(0.01, min(1.0, torchLevel)))
            d.unlockForConfiguration()
        } catch { /* ignore */ }
    }

    private func forceTorchOff() {
        guard let d = cameraDevice, d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            if d.torchMode != .off { d.torchMode = .off }
            d.unlockForConfiguration()
        } catch { /* ignore */ }
    }

    // MARK: - Brightness (supports YUV or BGRA)
    private func computeNormalizedBrightness(from pixelBuffer: CVPixelBuffer) -> CGFloat {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // Fast path: Y from bi-planar YUV
        if fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
           fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 1.0 }
            var sum: UInt64 = 0
            for r in 0..<h {
                let row = base.advanced(by: r * bpr).assumingMemoryBound(to: UInt8.self)
                var c = 0
                while c < w { sum &+= UInt64(row[c]); c += 2 } // light downsample
            }
            let samples = UInt64(h * ((w + 1) / 2))
            let meanY = CGFloat(sum) / CGFloat(samples) // 0..255
            return max(0, min(1, meanY / 255.0))
        }

        // BGRA downsample grid
        if fmt == kCVPixelFormatType_32BGRA {
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 1.0 }
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let step = 8
            var sum: Double = 0
            var count = 0
            for r in stride(from: 0, to: h, by: step) {
                let row = base.advanced(by: r * bpr).assumingMemoryBound(to: UInt8.self)
                for c in stride(from: 0, to: w, by: step) {
                    let i = c * 4
                    // Rec.709 luma
                    let y = 0.2126 * Double(row[i+2]) + 0.7152 * Double(row[i+1]) + 0.0722 * Double(row[i+0])
                    sum += y; count += 1
                }
            }
            if count == 0 { return 1.0 }
            return CGFloat(max(0.0, min(1.0, (sum / Double(count)) / 255.0)))
        }

        return 1.0
    }
}
