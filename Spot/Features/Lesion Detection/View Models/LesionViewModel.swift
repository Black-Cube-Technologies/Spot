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
    
    // Prevent repeated auto-captures per session/draft
    private var hasAutoCaptured = false
    
    // Updated: because frames are already rotated to portrait by videoRotationAngle,
    // Vision should see them as .up to avoid double-rotation.
    private let visionOrientation: CGImagePropertyOrientation = .up // Updated
    
    //private let diameterThresholdMM: CGFloat = 2000//100
    
    private let nearLimitWindowSize = 5
    private var lastNearLimitValue: [Bool] = []
    private var streakAnnounced = false
    
    @Published var validMeasurementValues = [LesionMeasurement]()
    @Published var  didAchieveModelValue = false
    var requiredValidMeasurements = 25
    
    var latestBoundingBox =  CGRect.zero
    
    private var enforceCircularMask = true
    private var detectionCompleteTime = Date()
    
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
        hasAutoCaptured = false
        // Default to 1× (maps to 2.0) on launch
        setPresetZoom1x(animated: false)
    }
    public func stop()  {
        camera.stop()
        didAchieveModelValue = false
        hasAutoCaptured = false
    }
    public func resetDraft(deleteTemp: Bool = false) {
        if deleteTemp, let url = lesion?.imageURL {
            try? LocalTempImageStore().removeTemp(at: url)
        }
        lesion = nil
        zoom = zoomMin
        didAchieveModelValue = false
        hasAutoCaptured = false
        emptyMeasurementValues()
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
            self.latestBoundingBox = lesionBL
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
            let previewNorm = layerNormRect(fromVision: object.boundingBox, pixelBuffer: pbForDetection, visionOrientation: visionOrientation) // Added
            
            await
            MainActor.run {
                //self.boxNorms.append(observation.copyWith(normBox: previewNorm)) // Updated: now preview-normalized (top-left)
                self.sizeText = self.measurer.format(m, units: self.units, decimals: 1)
                print("sizeText",sizeText)
                if let _ = self.didAchiveModeValue(m),!didAchieveModelValue{
                    didAchieveModelValue = true
                    // Take Camera Photo Here and Navigate to Next screen
                    camera.reconfigureToTriple4K {
                        self.detectionCompleteTime = Date()
                    }
//                    captureAndCreateDraft(pixelBuffer: pb,
//                                                  widthMM: val.0,
//                                                  heightMM: val.1,
//                                                  lesionRectBL: lesionBL)
                }
                
                // Auto-capture when bbox covers at least 30% of the circular ROI, model value achieved, focus is stable, and lesion is centered
                if self.didAchieveModelValue,
                   !self.hasAutoCaptured,
                   self.isCameraNotAdjustingFocus(),
                   Date().timeIntervalSince(detectionCompleteTime) > 2
                {
                    
                    if let ratio = self.bboxAreaRatioToROI(rBL: lesionBL, pixelBuffer: pbForDetection, orientation: self.visionOrientation) {
                        if ratio >= 0.3 {
                            if  self.isLesionCenteredInDetection(lesionBL) {
                                self.hasAutoCaptured = true
                                self.capturePhoto()
                            }
                            else{
                                self.toastMessage = "Keep lesion in center of frame"
                            }
                        }
                        
                    }
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
    
    // Computes the ratio of the given Vision bbox area to the circular ROI area, both measured in preview-layer normalized space.
    // Returns nil if previewLayer is unavailable or geometry is invalid.
    private func bboxAreaRatioToROI(rBL: CGRect, pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGFloat? {
        guard let pl = previewLayer else { return nil }
        let W = pl.bounds.width
        let H = pl.bounds.height
        guard W > 0, H > 0 else { return nil }

        // Convert Vision rect (bottom-left normalized in the image it processed) into preview-layer normalized (top-left)
        let rectInPreview01 = layerNormRect(fromVision: rBL, pixelBuffer: pixelBuffer, visionOrientation: orientation)
        if rectInPreview01.isNull || rectInPreview01.isEmpty { return nil }

        // Area of bbox as a fraction of preview layer
        let bboxAreaFractionOfPreview = max(0, rectInPreview01.width) * max(0, rectInPreview01.height)

        // Compute circular ROI area as a fraction of the preview layer area.
        // The circular mask is centered and its diameter is `DetectionConstants.roiFraction` of the shorter preview dimension.
        let s = min(W, H)
        let d = CGFloat(DetectionConstants.roiFraction)
        // Circle area = pi * (r^2) where r = (d * s) / 2
        let circleArea = .pi * pow((d * s) / 2.0, 2)
        let previewArea = W * H
        guard previewArea > 0 else { return nil }
        let roiAreaFractionOfPreview = circleArea / previewArea
        guard roiAreaFractionOfPreview > 0 else { return nil }

        // Ratio of bbox area to ROI area
        return bboxAreaFractionOfPreview / roiAreaFractionOfPreview
    }
    
    // Returns true if the bbox center is within a tolerance of the center of the detection buffer (normalized [0,1]).
    private func isLesionCenteredInDetection(_ rBL: CGRect, tolerance: CGFloat = 0.15) -> Bool {
        // rBL is already in Vision's normalized coordinates for the image used by the detector (pbForDetection)
        let cx = rBL.midX
        let cy = rBL.midY
        let dx = abs(cx - 0.5)
        let dy = abs(cy - 0.5)
        return max(dx, dy) <= tolerance
    }
    
    // Returns true when the camera is not actively adjusting focus.
    private func isCameraNotAdjustingFocus() -> Bool {
        return !(camera.getCameraDevice()?.isAdjustingFocus ?? true)
    }
    
    private func showInstructionsIfNeeded() {
        if didAchieveModelValue {
            self.toastMessage =  "Move closer to the lesion to capture the image"
            return
        }
        
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
            self.toastMessage = "Hold steady, measuring the lesion.. use zoom if necessary"
        }
    }
    
    private func didAchiveModeValue(_ m: LesionMeasurement) -> (Double,Double)? {
        if !(camera.getCameraDevice()?.isTooCloseToFocus ?? true)  && !didAchieveModelValue{
            //Only add
            validMeasurementValues.append(m)
            print(validMeasurementValues.count)
        }
        if validMeasurementValues.count >= requiredValidMeasurements{
            let w = validMeasurementValues.widthMode()?.value ?? 0
            let h = validMeasurementValues.heightMode()?.value ?? 0
            if w == 0 && h == 0{
                emptyMeasurementValues()
                return nil
            }
            return (w,h)
        }
        return nil
    }
    
    func emptyMeasurementValues(){
        if !didAchieveModelValue{
            validMeasurementValues = []
        }
    }
    
    
    
    func capturePhoto(){
        // Only capture when focus is stable
        if camera.getCameraDevice()?.isAdjustingFocus ?? false {
            return
        }
        camera.capturePhotoJPEG { fullImage in
            
            let widthMM = self.validMeasurementValues.widthMode()?.value ?? 0
            let heightMM = self.validMeasurementValues.heightMode()?.value ?? 0
            var enlargeFactor: CGFloat =  1
            if heightMM < 10 && widthMM < 10{
                enlargeFactor = 2.25
            }
            
            else if heightMM < 20 && widthMM < 20{
                enlargeFactor = 2
            }
            
            else if heightMM < 30 && widthMM < 30{
                enlargeFactor = 1.75
            }
            
            else if heightMM < 40 && widthMM < 40{
                enlargeFactor = 1.5
            }
            
            let cropped = ImageUtility.cropUIImage(fullImage, toNormalizedBL:  self.latestBoundingBox.scaledAboutCenter(widthFactor: enlargeFactor, heightFactor: enlargeFactor)) ?? fullImage
            //guard let cropped = ImageUtility.cropUIImage(image, toNormalizedBL: self.latestBoundingBox) else{return}
           
            let id = UUID().uuidString
            do {
                let fileURL = try LocalTempImageStore().saveTempJPEG(cropped, id: id, quality: 1)
                guard self.lesion == nil else { return }
                self.lesion = Lesion(
                    width:  widthMM,
                    height: heightMM,
                    imageURL: fileURL,
                    boundedBoxes: self.boxNorms.map(\.normBox) // keep if you still overlay later
                )
            } catch {
                print("Saving temp image failed: \(error)")
            }
        }
    }
    // Call this when your sizing logic decides to capture
    private func captureAndCreateDraft(pixelBuffer: CVPixelBuffer,
                                       widthMM: Double,
                                       heightMM: Double,
                                       lesionRectBL: CGRect) { // <— NEW param (Vision's normalized BL rect)
        //camera.captureProRAWPhoto { proRawPhoto  in
            guard let fullImage = ImageUtility.uiImage(from: pixelBuffer, orientation: self.visionOrientation) else { return }
            //let sizeMultiplier = ImageUtility.sizeMultiplier(between: fullImage, and: proRawPhoto)
            var shouldEnlargeRect =  false
            // Crop to the lesion (tight rectangle)
            if heightMM < 10 && widthMM < 10{
                shouldEnlargeRect = true
            }
            
            let cropped = ImageUtility.cropUIImage(fullImage, toNormalizedBL: shouldEnlargeRect ? lesionRectBL.scaledAboutCenter(widthFactor: 1.5, heightFactor: 1.5) : lesionRectBL) ?? fullImage

            let id = UUID().uuidString
            do {
                let fileURL = try LocalTempImageStore().saveTempJPEG(cropped, id: id, quality: 1)
                guard self.lesion == nil else { return }
                self.lesion = Lesion(
                    width:  widthMM,
                    height: heightMM,
                    imageURL: fileURL,
                    boundedBoxes: self.boxNorms.map(\.normBox) // keep if you still overlay later
                )
            } catch {
                print("Saving temp image failed: \(error)")
            }
        //}
        //
        
    }

}
