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
    @Published public private(set) var boxNorms: [LesionModel] = [] // Updated semantic
    @Published public var units: UnitSystem = .metric
    @Published public var toastMessage:String?
    @Published public var lesion:Lesion?
    
    @Published public private(set) var zoom: CGFloat = 1.0
    public private(set) var zoomMin: CGFloat = 1.0
    public private(set) var zoomMax: CGFloat = 5.0
    
    private var zoomCtl: CameraZoomControlling?
    
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
    
    //private let diameterThresholdMM: CGFloat = 2000//100
    
    private let nearLimitWindowSize = 5
    private var lastNearLimitValue: [Bool] = []
    private var streakAnnounced = false
    
    @Published var validMeasurementValues = [LesionMeasurement]()
    var requiredValidMeasurements = 20
    
    private var enforceCircularMask = true
    
    public init(camera: CameraStreaming,
                detector: LesionDetecting,
                measurer: SizeMeasuring = MeasurementService(),
                calibrator: CalibrationProviding = CalibrationService()) {
        self.camera = camera
        self.detector = detector
        self.measurer = measurer
        self.calibrator = calibrator
        
        // Unified RGB(+Depth) stream
        if let z = camera as? CameraZoomControlling {
            self.zoomCtl = z
            self.zoomMin = z.minZoomFactor
            self.zoomMax = z.maxZoomFactor
            z.currentZoom
                .receive(on: DispatchQueue.main)
                .sink { [weak self] v in self?.zoom = v }
                .store(in: &bag)
        }
        
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
    
    public func start() {
        camera.start()
        resetDraft()
        // Default to 1× (maps to 2.0) on launch
        setPresetZoom1x(animated: false)
    }
    public func stop()  {
        camera.stop()
    }
    public func resetDraft(deleteTemp: Bool = false) {
        if deleteTemp, let url = lesion?.imageURL {
            try? LocalTempImageStore().removeTemp(at: url)
        }
        lesion = nil
        self.validMeasurementValues.removeAll()
        zoom = zoomMin
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
        showInstructionsIfNeeded()
        
        let pbForDetection: CVPixelBuffer
        if enforceCircularMask, let masked = ImageUtility.makeCircularMaskedPixelBuffer(
            from: pb,
            previewSize: previewLayer!.bounds.size,
            gravity: previewLayer!.videoGravity,        // usually .resizeAspectFill
            diameterFractionInPreview: DetectionConstants.roiFraction,      // your 0..1 UI slider / constant
            centerInPreview01: CGPoint(x: 0.5, y: 0.5)
        ) {
            pbForDetection = masked
        } else {
            pbForDetection = pb
        }
        
        let observations = await detector.detect(in: pbForDetection, orientation: visionOrientation) // Updated
        
        self.boxNorms.removeAll()
        for observation in observations {
            
            let object = observation.object
            let lesionBL = object.boundingBox
            print("observations",lesionBL)
            // Per-frame depth → calibration (if available)
            if let d = pack.depthData,
               let depthCal = DepthCalibratorAVF.calibration(for: pack.sampleBuffer,
                                                             depthData: d,
                                                             roiNorm: object.boundingBox)?.calib {
                let mmX = emaX.push(depthCal.mmPerPixelX)
                 let mmY = emaY.push(depthCal.mmPerPixelY)
                calib = PixelCalibration(mmPerPixelX: mmX, mmPerPixelY: mmY)
            }
            
            
            let m = measurer.measure(from: object, imageSize: imSize, calib: calib, fillRatio: fillRatio)
            
            // Convert Vision bbox → preview-layer normalized (top-left) so overlay aligns under any gravity/crop.
            //let previewNorm = layerNormRect(fromVision: object.boundingBox, pixelBuffer: pbForDetection, visionOrientation: visionOrientation) // Added
            
            await
            MainActor.run {
                //toastMessage =  pushDiameterAndShouldToast(m.equivDiameterMM) ? "Move further away" : nil
                //self.boxNorms.append(observation.copyWith(normBox: previewNorm)) // Updated: now preview-normalized (top-left)
                self.sizeText = self.measurer.format(m, units: self.units, decimals: 1)
                if let val = self.didAchiveModeValue(m){
                    // Take Camera Photo Here and Navigate to Next screen
                    captureAndCreateDraft(pixelBuffer: pb,
                                                  widthMM: val.0,
                                                  heightMM: val.1,
                                                  lesionRectBL: lesionBL)
                }
            }
        }
    }
    
    public func setZoom(_ v: CGFloat, animated: Bool = true) {
        zoomCtl?.setZoom(v, animated: animated, rate: 10.0)
    }
    // MARK: - Preset Zooms (maps to 2.0x, 6.0x, 10.0 digital zoom)
    public func setPresetZoom1x(animated: Bool = true) {
        setZoom(2.0, animated: animated)
        emptyMeasurementValues()
    }
    public func setPresetZoom2x(animated: Bool = true) {
        setZoom(6.0, animated: animated)
        emptyMeasurementValues()
    }
    public func setPresetZoom3x(animated: Bool = true) {
        setZoom(10.0, animated: animated)
        emptyMeasurementValues()
    }
    
    public func zoomIn(animated: Bool = true) {
        let target = zoom == zoomMax ? zoomMin : zoomMax
        setZoom(target, animated: animated)
        emptyMeasurementValues()
    }
    
    // MARK: - Coordinate conversion
    // Vision gives [0,1] with origin at bottom-left of the image it processed.
    // Preview layer expects metadata-normalized with top-left origin, then we normalize by layer bounds.
    private func layerNormRect(fromVision rBL: CGRect,
                               pixelBuffer pb: CVPixelBuffer,
                               visionOrientation o: CGImagePropertyOrientation) -> CGRect {
        guard let pl = previewLayer else { return .null }
        let W = pl.bounds.width, H = pl.bounds.height
        guard W > 0, H > 0 else { return .null }

        // Pixel buffer dimensions (unrotated)
        let w0 = CGFloat(CVPixelBufferGetWidth(pb))
        let h0 = CGFloat(CVPixelBufferGetHeight(pb))

        // Vision bbox is in the oriented image space:
        // swap width/height when orientation rotates 90°.
        let rotates90: Bool = {
            switch o {
            case .left, .right, .leftMirrored, .rightMirrored: return true
            default: return false
            }
        }()
        let w = rotates90 ? h0 : w0
        let h = rotates90 ? w0 : h0
        guard w > 0, h > 0 else { return .null }

        // Vision (bottom-left) → top-left
        let rTL = CGRect(x: rBL.minX,
                         y: 1.0 - rBL.maxY,
                         width: rBL.width,
                         height: rBL.height)

        // Image-space (px) in *Vision's oriented image*
        let imgRect = CGRect(x: rTL.minX * w,
                             y: rTL.minY * h,
                             width:  rTL.width  * w,
                             height: rTL.height * h)

        // Map oriented image (w×h) → preview layer (W×H) using aspectFill
        let scale  = max(W / w, H / h)
        let scaledW = w * scale
        let scaledH = h * scale
        let tx = (W - scaledW) * 0.5
        let ty = (H - scaledH) * 0.5

        let layerRect = CGRect(x: imgRect.minX * scale + tx,
                               y: imgRect.minY * scale + ty,
                               width:  imgRect.width  * scale,
                               height: imgRect.height * scale)

        // Normalize to [0,1] in layer space
        return CGRect(x: layerRect.minX / W,
                      y: layerRect.minY / H,
                      width:  layerRect.width  / W,
                      height: layerRect.height / H)
    }
    
    
    private func showInstructionsIfNeeded() {
        guard let camera = camera.getCameraDevice() else {return}
        let isNear = camera.isTooCloseToFocus
        
        lastNearLimitValue.append(isNear)
        if lastNearLimitValue.count > nearLimitWindowSize {lastNearLimitValue = lastNearLimitValue.suffix(nearLimitWindowSize)}
        // Only if we have exactly 10 recent values and ALL are > threshold
        if lastNearLimitValue.count == nearLimitWindowSize,
           lastNearLimitValue.allSatisfy({ $0 }) {
            //            if !streakAnnounced {
            //                streakAnnounced = true
            self.toastMessage =  "Move further away from the lesion"// fire once per streak
            //}
        } else {
            // Any miss or <10 values resets the streak so we can fire again later
            self.toastMessage = nil
        }
    }
    
    private func didAchiveModeValue(_ m: LesionMeasurement) -> (Double,Double)? {
        if !(camera.getCameraDevice()?.isTooCloseToFocus ?? true) {
            //Only add
            validMeasurementValues.append(m)
            print(validMeasurementValues.count)
        }
        if validMeasurementValues.count >= requiredValidMeasurements{
            let w = validMeasurementValues.widthMode()?.value ?? 0
            let h = validMeasurementValues.heightMode()?.value ?? 0
            return (w,h)
        }
        return nil
    }
    
    private func emptyMeasurementValues(){
        validMeasurementValues = []
    }
    
    // Call this when your sizing logic decides to capture
    private func captureAndCreateDraft(pixelBuffer: CVPixelBuffer,
                                       widthMM: Double,
                                       heightMM: Double,
                                       lesionRectBL: CGRect) { // <— NEW param (Vision's normalized BL rect)
        guard let fullImage = ImageUtility.uiImage(from: pixelBuffer, orientation: visionOrientation) else { return }

        // Crop to the lesion (tight rectangle)
        let cropped = ImageUtility.cropUIImage(fullImage, toNormalizedBL: lesionRectBL) ?? fullImage

        let id = UUID().uuidString
        do {
            let fileURL = try LocalTempImageStore().saveTempJPEG(cropped, id: id, quality: 0.92)
            guard lesion == nil else { return }
            self.lesion = Lesion(
                width:  widthMM,
                height: heightMM,
                imageURL: fileURL,
                boundedBoxes: boxNorms.map(\.normBox) // keep if you still overlay later
            )
        } catch {
            print("Saving temp image failed: \(error)")
        }
    }

}
