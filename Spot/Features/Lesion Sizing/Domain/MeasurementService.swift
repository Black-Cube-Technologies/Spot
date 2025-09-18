import Vision
import CoreGraphics



public final class MeasurementService: SizeMeasuring {
    public init() {}

    @inline(__always)
    private func pixelRect(from normalized: CGRect, imageSize: CGSize) -> CGRect {
        let w = normalized.width  * imageSize.width
        let h = normalized.height * imageSize.height
        let x = normalized.minX   * imageSize.width
        let yBL = normalized.minY * imageSize.height
        let y = imageSize.height - yBL - h // flip to top-left for drawing
        return CGRect(x: x, y: y, width: w, height: h)
    }

    public func measure(from obs: VNRecognizedObjectObservation,
                        imageSize: CGSize,
                        calib: PixelCalibration,
                        fillRatio: CGFloat = 0.72) -> LesionMeasurement {

        let pr = pixelRect(from: obs.boundingBox, imageSize: imageSize)

        let boxWmm = pr.width  * calib.mmPerPixelX
        let boxHmm = pr.height * calib.mmPerPixelY

        let s = sqrt(max(fillRatio, 0))
        let widthMM  = boxWmm * s
        let heightMM = boxHmm * s
        let areaMM2  = (boxWmm * boxHmm) * max(fillRatio, 0)

        // Use inscribed circle of the bbox for a more robust equivalent diameter on small, circular lesions.
        // Compute diameter in pixels as the smaller side of the pixel rect, then convert using geometric mean of mm/px.
        let dPx = min(pr.width, pr.height)
        let mmPerPxForD = sqrt(max(calib.mmPerPixelX, 0) * max(calib.mmPerPixelY, 0))
        let dmm = dPx * mmPerPxForD

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
