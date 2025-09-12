import Vision
import CoreGraphics



public final class MeasurementService: SizeMeasuring {
    public init() {}

    private func activeRGBSize(from pb: CVPixelBuffer) -> CGSize {
        if let ap = CMGetAttachment(pb, key: kCVImageBufferCleanApertureKey, attachmentModeOut: nil)
            as? [AnyHashable: Any],
           let w = (ap[kCVImageBufferCleanApertureWidthKey as String] as? NSNumber)?.doubleValue,
           let h = (ap[kCVImageBufferCleanApertureHeightKey as String] as? NSNumber)?.doubleValue {
            return CGSize(width: w, height: h)
        }
        return CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
    }

    /// Swap W/H when Vision orientation is 90° rotated (left/right, mirrored variants).
    private func orientedSize(for raw: CGSize, orientation o: CGImagePropertyOrientation) -> CGSize {
        switch o {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: raw.height, height: raw.width)
        default:
            return raw
        }
    }

    /// Use Vision helper + oriented active size (bottom-left origin; width/height correct).
    func pixelRect(from normalized: CGRect,
                   pixelBuffer pb: CVPixelBuffer,
                   visionOrientation: CGImagePropertyOrientation) -> CGRect {
        let raw = activeRGBSize(from: pb)
        let img = orientedSize(for: raw, orientation: visionOrientation)
        // Width/height are now the same geometry Vision used
        return VNImageRectForNormalizedRect(normalized, Int(img.width), Int(img.height))
    }

    public func measure(from obs: VNRecognizedObjectObservation,
                        pixelBuffer pb: CVPixelBuffer,
                        visionOrientation: CGImagePropertyOrientation,
                        calib: PixelCalibration,
                        fillRatio: CGFloat = 0.72) -> LesionMeasurement {

        let pr = pixelRect(from: obs.boundingBox,
                           pixelBuffer: pb,
                           visionOrientation: visionOrientation)

        let normAR = obs.boundingBox.width / max(obs.boundingBox.height, 1e-6)
        let prAR   = pr.width / max(pr.height, 1e-6)
        print("normAR:", normAR, "prAR:", prAR,
              "orientedW×H:",
              orientedSize(for: activeRGBSize(from: pb),
                           orientation: visionOrientation))

        let boxWmm = pr.width  * calib.mmPerPixelX
        let boxHmm = pr.height * calib.mmPerPixelY

        let s = sqrt(max(fillRatio, 0))
        let widthMM  = boxWmm * s
        let heightMM = boxHmm * s
        let areaMM2  = (boxWmm * boxHmm) * max(fillRatio, 0)
        let dmm      = (4.0 * areaMM2 / .pi).squareRoot()
        
        return .init(bboxNorm: obs.boundingBox,
                     pixelRect: pr,
                     widthMM: widthMM,
                     heightMM: heightMM,
                     areaMM2: areaMM2,
                     equivDiameterMM: dmm)
    }

    public func format(_ m: LesionMeasurement, units: UnitSystem, decimals: Int = 1) -> String {
        let f = { (v: CGFloat) in String(format: "%.\(decimals)f", v) }
        func mmToCM(_ mm: CGFloat) -> CGFloat { mm / 10 }
        func mmToIn(_ mm: CGFloat) -> CGFloat { mm / 25.4 }
        func mm2ToCM2(_ mm2: CGFloat) -> CGFloat { mm2 / 100 }
        func mm2ToIN2(_ mm2: CGFloat) -> CGFloat { mm2 / 645.16 }

        switch units {
        case .metric:
            return "≈ \(f(mmToCM(m.widthMM))) × \(f(mmToCM(m.heightMM))) cm • \(f(mm2ToCM2(m.areaMM2))) cm² • d≈\(f(mmToCM(m.equivDiameterMM))) cm"
        case .imperial:
            return "≈ \(f(mmToIn(m.widthMM))) × \(f(mmToIn(m.heightMM))) in • \(f(mm2ToIN2(m.areaMM2))) in² • d≈\(f(mmToIn(m.equivDiameterMM))) in"
        }
    }
    
    
}
