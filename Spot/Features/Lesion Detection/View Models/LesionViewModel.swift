import Foundation
import UIKit
import Combine
import AVFoundation
import Vision

// Added: tiny EMA for smoothing mm/px
private final class EMA {
    private var v: CGFloat?
    private let a: CGFloat
    init(halfLifeFrames: Int = 6) { self.a = 2.0 / CGFloat(halfLifeFrames + 1) }
    func push(_ x: CGFloat) -> CGFloat {
        if let v { self.v = (1 - a) * v + a * x } else { self.v = x }
        return self.v!
    }
}

@MainActor
public final class LesionViewModel: ObservableObject {
    
    // MARK: Published UI state
    @Published public private(set) var sizeText: String = "—"
    // Updated: boxNorm now means **preview-layer normalized (top-left)** so it matches what you draw.
    @Published public private(set) var boxNorm: CGRect = .null // Updated semantic
    @Published public var units: UnitSystem = .metric
    @Published public var toastMessage:String?
    @Published public var lesion:Lesion?
    
    // MARK: Dependencies
    private let camera: CameraStreaming
    private let detector: LesionDetecting
    private let measurer: SizeMeasuring
    private let calibrator: CalibrationProviding
    
    // MARK: Config
    private var calib = PixelCalibration(mmPerPixel: 0.10)  // fallback when no depth
    private var fillRatio: CGFloat = 0.72
    
    // MARK: Internals
    private var bag = Set<AnyCancellable>()
    private var lastImageSize: CGSize = .zero
    
    // Added: smoothing for per-frame mm/px (depth noise)
    private let emaX = EMA(halfLifeFrames: 6) // Added
    private let emaY = EMA(halfLifeFrames: 6) // Added
    
    // Added: keep a handle to the preview layer so we can convert rects correctly
    private weak var previewLayer: AVCaptureVideoPreviewLayer? // Added
    
    // Updated: because frames are already rotated to portrait by videoRotationAngle,
    // Vision should see them as .up to avoid double-rotation.
    private let visionOrientation: CGImagePropertyOrientation = .up // Updated
    
    private let diameterThresholdMM: CGFloat = 100
    private let diameterWindowSize = 5
    private var lastDiameters: [CGFloat] = []
    private var streakAnnounced = false
    private let confidenceThreshold: Float = 0.85
    
    private var validMeasurementValues = [LesionMeasurement]()
    
    public init(camera: CameraStreaming,
                detector: LesionDetecting,
                measurer: SizeMeasuring = MeasurementService(),
                calibrator: CalibrationProviding = CalibrationService()) {
        self.camera = camera
        self.detector = detector
        self.measurer = measurer
        self.calibrator = calibrator
        
        // Unified RGB(+Depth) stream
        camera.frames
            .throttle(for: .milliseconds(120), scheduler: DispatchQueue.global(), latest: true)
            .sink { [weak self] pack in
                Task.detached { [weak self] in
                    await self?.process(pack)
                }
            }
            .store(in: &bag)
    }
    
    // MARK: - Public API
    // Added: call this from the view once you create the preview layer
    public func attach(previewLayer: AVCaptureVideoPreviewLayer) { // Added
        self.previewLayer = previewLayer
    }
    
    public func start() { camera.start() }
    public func stop()  {
        camera.stop()
        resetDraft()
    }
    public func resetDraft(deleteTemp: Bool = false) {
        if deleteTemp, let url = lesion?.imageURL {
            try? LocalTempImageStore().removeTemp(at: url)
        }
        lesion = nil
        self.validMeasurementValues.removeAll()
    }
    
    public func setUnits(_ u: UnitSystem)  { units = u }
    public func setFillRatio(_ r: CGFloat) { fillRatio = max(0, min(1, r)) }
    
    /// Two-tap fallback calibration for devices/flows without depth.
    public func calibrate(knownMM: CGFloat,
                          p1InPreview: CGPoint, p2InPreview: CGPoint,
                          previewLayer: AVCaptureVideoPreviewLayer) {
        guard lastImageSize != .zero else { return }
        let mmPx = calibrator.mmPerPixel(knownMM: knownMM,
                                         p1InPreview: p1InPreview, p2InPreview: p2InPreview,
                                         imageSize: lastImageSize, previewLayer: previewLayer)
        calib = PixelCalibration(mmPerPixel: mmPx)
    }
    
    // Expose session for preview binding
    public var session: AVCaptureSession { camera.session }
    
    // MARK: - Processing
    private func process(_ pack: FramePack) async {
        guard let pb = CMSampleBufferGetImageBuffer(pack.sampleBuffer) else { return }
        let imSize = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        self.lastImageSize = imSize
        
        // Detection with correct orientation (see comment above)
        let observations = await detector.detect(in: pb, orientation: visionOrientation) // Updated
        guard let best = observations.max(by: { $0.confidence < $1.confidence }) else {
            
            return }
        
        // Per-frame depth → calibration (if available)
        if let d = pack.depthData,
           let depthCal = DepthCalibratorAVF.calibration(for: pack.sampleBuffer,
                                                         depthData: d,
                                                         roiNorm: best.boundingBox) {
            let mmX = emaX.push(depthCal.mmPerPixelX)
            let mmY = emaY.push(depthCal.mmPerPixelY)
            calib = PixelCalibration(mmPerPixelX: mmX, mmPerPixelY: mmY)
        }
        
        let m = measurer.measure(from: best, imageSize: imSize, calib: calib, fillRatio: fillRatio)
        
        // Convert Vision bbox → preview-layer normalized (top-left) so overlay aligns under any gravity/crop.
        let previewNorm = layerNormRect(fromVision: best.boundingBox, pixelBuffer: pb, visionOrientation: visionOrientation) // Added
        
        await MainActor.run {
            toastMessage =  pushDiameterAndShouldToast(m.equivDiameterMM) ? "Move further away" : nil
            if best.confidence >= confidenceThreshold{
                self.boxNorm  = previewNorm // Updated: now preview-normalized (top-left)
                self.sizeText = self.measurer.format(m, units: self.units, decimals: 1)
                if let val = self.didAchiveModeValue(m){
                    captureAndCreateDraft(pack: pack, widthMM: val.0, heightMM: val.1)
                    //Take Camera Photo Here and Navigate to Next screen
                }
            }
            else{
                self.boxNorm = .null
            }
        }
    }
    
    // MARK: - Coordinate conversion
    // Vision gives [0,1] with origin at bottom-left of the image it processed.
    // Preview layer expects metadata-normalized with top-left origin, then we normalize by layer bounds.
    private func layerNormRect(fromVision rBL: CGRect,
                               pixelBuffer pb: CVPixelBuffer,
                               visionOrientation o: CGImagePropertyOrientation) -> CGRect {
        
        guard let pl = previewLayer, pl.bounds.width > 0, pl.bounds.height > 0 else { return .null }
        
        // 1) Vision normalized (bottom-left) -> metadata normalized (top-left)
        let metaTL = CGRect(
            x: rBL.minX,
            y: 1.0 - rBL.maxY,
            width: rBL.width,
            height: rBL.height
        )
        
        // 2) Metadata -> layer rect (accounts for aspect fill/fit, clean aperture, rotation, mirroring)
        let layerRect = pl.layerRectConverted(fromMetadataOutputRect: metaTL)
        
        // 3) Normalize to [0,1] in layer space for your overlay
        let W = pl.bounds.width, H = pl.bounds.height
        return CGRect(x: layerRect.minX / W,
                      y: layerRect.minY / H,
                      width: layerRect.width / W,
                      height: layerRect.height / H)
    }
    
    private func uiImageOrientation() -> UIImage.Orientation {
        let vo = previewLayer?.connection?.videoOrientation ?? .portrait
        // Choose camera position (back by default)
        let position: AVCaptureDevice.Position = (camera.session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?.device.position) ?? .back
        
        switch (vo, position) {
        case (.portrait, .front): return .leftMirrored
        case (.portrait, _):      return .right
        case (.portraitUpsideDown, .front): return .rightMirrored
        case (.portraitUpsideDown, _):      return .left
        case (.landscapeRight, .front):     return .downMirrored
        case (.landscapeRight, _):          return .up
        case (.landscapeLeft, .front):      return .upMirrored
        case (.landscapeLeft, _):           return .down
        @unknown default:                   return .right
        }
    }
    
    
    @inline(__always)
    private func pushDiameterAndShouldToast(_ d: CGFloat) -> Bool {
        lastDiameters.append(d)
        if lastDiameters.count > diameterWindowSize { lastDiameters = lastDiameters.suffix(diameterWindowSize) }
        
        // Only if we have exactly 10 recent values and ALL are > threshold
        if lastDiameters.count >= diameterWindowSize,
           lastDiameters.allSatisfy({ $0 > diameterThresholdMM }) {
            //            if !streakAnnounced {
            //                streakAnnounced = true
            return true           // fire once per streak
            //}
        } else {
            // Any miss or <10 values resets the streak so we can fire again later
            streakAnnounced = false
        }
        return false
    }
    
    private func didAchiveModeValue(_ m: LesionMeasurement) -> (Double,Double)? {
        if m.equivDiameterMM < diameterThresholdMM {
            validMeasurementValues.append(m)
            print(validMeasurementValues.count)
        }
        if validMeasurementValues.count >= 25{
            let w = validMeasurementValues.widthMode()?.value ?? 0
            let h = validMeasurementValues.heightMode()?.value ?? 0
            return (w,h)
        }
        return nil
    }
    
    // Call this when your sizing logic decides to capture
    private func captureAndCreateDraft(pack: FramePack,widthMM: Double, heightMM: Double) {
        
        guard let image = ImageUtility.uiImage(from: pack.sampleBuffer, orientation: uiImageOrientation()) else {return}
        
        let id = UUID().uuidString
        do {
            let fileURL = try LocalTempImageStore().saveTempJPEG(image, id: id, quality: 0.92)
            guard lesion == nil else { return }
            self.lesion = Lesion(
                width: widthMM,
                height: heightMM,
                imageURL: fileURL
            )
        } catch {
            // Surface to UI (toast/snackbar) as you prefer
            print("Saving temp image failed: \(error)")
        }
    }
}
