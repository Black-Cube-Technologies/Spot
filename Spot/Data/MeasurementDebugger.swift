//
//  MeasurementDebugger.swift
//  Spot
//
//  Created by Hasan on 12/09/2025.
//


import AVFoundation
import Vision
import CoreMedia
import simd

enum MeasurementDebugger {

    // MARK: - Public entry
    static func run(
        pixelBuffer pb: CVPixelBuffer,
        depthData dd: AVDepthData,
        bbox: CGRect,                              // observation.boundingBox (normalized, BL origin)
        orientation: CGImagePropertyOrientation,   // the SAME you pass to Vision
        zoom: CGFloat,                             // captureDevice.videoZoomFactor
        label: String = "DBG"
    ) {
        let rawSize = activeRGBSize(from: pb)
        let imgSize = orientedSize(for: rawSize, orientation: orientation)

        // 1) Denormalize bbox using the SAME oriented geometry Vision used
        let pr = VNImageRectForNormalizedRect(bbox, Int(imgSize.width), Int(imgSize.height))

        // 2) Depth patch from the SAME region (account for top-left addressing in depth)
        guard let zStats = depthStats(in: pr, rgbSize: imgSize, depthData: dd) else {
            print("❌ \(label) depthStats nil")
            return
        }

        // 3) Intrinsics mapped to RGB with uniform scale + optional 90° swap, then apply zoom
        guard let (fx, fy) = fxFyForRGB(from: dd, rgbSize: imgSize) else {
            print("❌ \(label) fx/fy not available")
            return
        }
        let fxZ = fx * max(1, zoom)
        let fyZ = fy * max(1, zoom)

        // 4) Choose Z (depth) → mm/px; try P75 to reduce “raised bump” bias
        let zMM = zStats.p75MM
        let mmPerPixelX = zMM / fxZ
        let mmPerPixelY = zMM / fyZ

        let widthMM  = Double(pr.width)  * mmPerPixelX
        let heightMM = Double(pr.height) * mmPerPixelY

        // 5) Logs we need (one line each)
        let normAR = bbox.width / max(bbox.height, 1e-6)
        let prAR   = pr.width / max(pr.height, 1e-6)
        let imgAR  = imgSize.width / imgSize.height
        let anisotropy = max(mmPerPixelX, mmPerPixelY) / max(min(mmPerPixelX, mmPerPixelY), 1e-9)

        print("—— \(label) FRAME ———————————————————————————————")
        print("orientedW×H:", imgSize, "rawW×H:", rawSize, "orientation:", orientation.rawValue, "zoom:", zoom)
        print("bboxNorm:", bbox, "normAR:", normAR, "→ pr(px):", pr, "prAR:", prAR, "imgAR:", imgAR, " prAR/imgAR:", prAR / imgAR)
        print("K→ fx,fy (ref→rgb, uniform scale + swap):", fx, fy, "→ zoomed:", fxZ, fyZ)
        print("Depth stats (mm): min:", zStats.minMM, "p50:", zStats.p50MM, "p75:", zStats.p75MM, "max:", zStats.maxMM)
        print("mm/px X:", mmPerPixelX, "Y:", mmPerPixelY, "anisotropy:", anisotropy)
        print("SIZE mm  width:", widthMM, "height:", heightMM)
    }

    // MARK: - Helpers

    // Clean aperture (active video) in buffer orientation
    private static func activeRGBSize(from pb: CVPixelBuffer) -> CGSize {
        if let ap = CMGetAttachment(pb,
                                    key: kCVImageBufferCleanApertureKey,
                                    attachmentModeOut: nil) as? [AnyHashable: Any],
           let w = (ap[kCVImageBufferCleanApertureWidthKey as String] as? NSNumber)?.doubleValue,
           let h = (ap[kCVImageBufferCleanApertureHeightKey as String] as? NSNumber)?.doubleValue {
            return CGSize(width: w, height: h)
        }
        return CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
    }

    // Swap W/H when Vision orientation is 90°
    private static func orientedSize(for raw: CGSize, orientation o: CGImagePropertyOrientation) -> CGSize {
        switch o {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: raw.height, height: raw.width)
        default:
            return raw
        }
    }

    // Intrinsics mapped to RGB geometry with UNIFORM scale; swap axes if 90° rotated
    private static func fxFyForRGB(from depthData: AVDepthData, rgbSize: CGSize) -> (CGFloat, CGFloat)? {
        guard let cc = depthData.cameraCalibrationData else { return nil }
        let K = cc.intrinsicMatrix
        let ref = cc.intrinsicMatrixReferenceDimensions
        let rw = CGFloat(ref.width), rh = CGFloat(ref.height)
        let w  = rgbSize.width,      h  = rgbSize.height

        let fxRef = CGFloat(K[0,0])
        let fyRef = CGFloat(K[1,1])

        let eps: CGFloat = 0.02
        let arRef = rw / rh
        let arRGB = w / h
        let isRot90 = abs(arRGB - (rh/rw)) < eps

        let rW = isRot90 ? rh : rw
        let rH = isRot90 ? rw : rh
        let s: CGFloat = (arRGB >= (rW/rH)) ? (w / rW) : (h / rH)

        let fx = (isRot90 ? fyRef : fxRef) * s
        let fy = (isRot90 ? fxRef : fyRef) * s
        guard fx.isFinite, fy.isFinite, fx > 0, fy > 0 else { return nil }
        return (fx, fy)
    }

    // Depth stats for ROI in RGB pixels; handles Y flip (depth = top-left, Vision = bottom-left)
    private static func depthStats(in pr: CGRect, rgbSize: CGSize, depthData: AVDepthData) -> (minMM: Double, p50MM: Double, p75MM: Double, maxMM: Double)? {
        let dPB = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(dPB, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dPB, .readOnly) }

        // Depth map size
        let dw = CVPixelBufferGetWidth(dPB)
        let dh = CVPixelBufferGetHeight(dPB)

        // Map RGB rect -> depth rect (scale + Y flip)
        let sx = CGFloat(dw) / rgbSize.width
        let sy = CGFloat(dh) / rgbSize.height
        let rw = pr.width  * sx
        let rh = pr.height * sy
        let rx = pr.origin.x * sx
        let ry = CGFloat(dh) - (pr.origin.y * sy) - rh     // Y flip

        let rD = CGRect(x: rx, y: ry, width: rw, height: rh).integral
        if rD.isNull || rD.width < 2 || rD.height < 2 { return nil }

        // Sample a decimated grid for speed
        let step = max(1, Int(min(rD.width, rD.height) / 64))
        var vals = [Float]()
        vals.reserveCapacity(Int((rD.width/CGFloat(step)) * (rD.height/CGFloat(step))))

        guard let base = CVPixelBufferGetBaseAddress(dPB) else { return nil }
        let strideX = CVPixelBufferGetBytesPerRow(dPB) / MemoryLayout<Float32>.size
        let buf = base.assumingMemoryBound(to: Float32.self)

        for j in stride(from: Int(rD.minY), through: Int(rD.maxY) - 1, by: step) {
            let row = buf + j * strideX
            for i in stride(from: Int(rD.minX), through: Int(rD.maxX) - 1, by: step) {
                let z = row[i]
                if z.isFinite, z > 0 { vals.append(z) }
            }
        }
        if vals.isEmpty { return nil }

        // AVDepthData depth often in meters; convert to mm if needed
        // Heuristic: if median < 10, assume meters.
        vals.sort()
        let mid = vals[vals.count/2]
        let unitToMM: Double = (Double(mid) < 10.0) ? 1000.0 : 1.0
        func q(_ p: Double) -> Double {
            let idx = Int((p * Double(vals.count - 1)).rounded())
            return Double(vals[idx]) * unitToMM
        }
        return (minMM: Double(vals.first!) * unitToMM,
                p50MM: q(0.50),
                p75MM: q(0.75),
                maxMM: Double(vals.last!) * unitToMM)
    }
}

private extension CGImagePropertyOrientation {
    var rawValue: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .upMirrored: return "upMirrored"
        case .downMirrored: return "downMirrored"
        case .leftMirrored: return "leftMirrored"
        case .rightMirrored:return "rightMirrored"
        @unknown default:   return "unknown"
        }
    }
}
