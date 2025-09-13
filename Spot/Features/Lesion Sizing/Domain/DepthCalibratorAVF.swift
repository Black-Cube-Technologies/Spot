import AVFoundation
import Vision
import simd
import CoreVideo
import CoreMedia

public struct DepthSnapshot {
    public let calib: PixelCalibration
    public let zMM: CGFloat
}

public enum DepthCalibratorAVF {

    public static func calibration(for sampleBuffer: CMSampleBuffer,
                                   depthData inDepth: AVDepthData?,
                                   roiNorm: CGRect) -> DepthSnapshot? {
        guard let depthData = inDepth else { return nil }

        // --- 1) Compute ROI in RGB pixels
        guard let img = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let iw = CGFloat(CVPixelBufferGetWidth(img))
        let ih = CGFloat(CVPixelBufferGetHeight(img))
        let roiPx = VNImageRectForNormalizedRect(roiNorm, Int(iw), Int(ih))

        // --- 2) Map ROI into depth map resolution (Float32)
        let depth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let dm   = depth.depthDataMap
        CVPixelBufferLockBaseAddress(dm, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dm, .readOnly) }

        let dw = CGFloat(CVPixelBufferGetWidth(dm))
        let dh = CGFloat(CVPixelBufferGetHeight(dm))
        let sx = dw / iw
        let sy = dh / ih
        let rD = CGRect(x: roiPx.origin.x * sx,
                        y: roiPx.origin.y * sy,
                        width: roiPx.size.width * sx,
                        height: roiPx.size.height * sy).integral

        let stride = CVPixelBufferGetBytesPerRow(dm) / MemoryLayout<Float32>.size
        guard let base = CVPixelBufferGetBaseAddress(dm) else { return nil }
        let ptr    = base.assumingMemoryBound(to: Float32.self)

        // --- 3) Median Z (meters) with sub-sampling for speed
        var zs: [Float] = []
        let x0 = max(0, Int(rD.minX)), x1 = min(Int(dw) - 1, Int(rD.maxX))
        let y0 = max(0, Int(rD.minY)), y1 = min(Int(dh) - 1, Int(rD.maxY))

        var y = y0
        while y <= y1 {
            let row = ptr + y * stride
            var x = x0
            while x <= x1 {
                let z = row[x]
                if z.isFinite && z > 0 { zs.append(z) }
                x += 2
            }
            y += 2
        }
        guard let zMedianM = zs.median else { return nil }
        let zMM = CGFloat(zMedianM * 1000.0)

        // --- 4) Get intrinsics (fx, fy) in **RGB pixel units**
        guard let (fx, fy) = intrinsicsPixels(sampleBuffer: sampleBuffer,
                                              depthData: depthData,
                                              rgbSize: CGSize(width: iw, height: ih)) else {
            return nil
        }

        // --- 5) mm/px from Z (pinhole: mmPerPixel = Z(mm) / f(px))
        let calib = PixelCalibration(mmPerPixelX: zMM / fx,
                                     mmPerPixelY: zMM / fy)
        return DepthSnapshot(calib: calib, zMM: zMM)
    }
  
    
    private static func intrinsicsPixels(sampleBuffer: CMSampleBuffer,
                                         depthData: AVDepthData,
                                         rgbSize: CGSize) -> (CGFloat, CGFloat)? {
        // (A) Best source: depth calibration data (scale to RGB size)
        if let cc = depthData.cameraCalibrationData {
            let K   = cc.intrinsicMatrix
            let ref = cc.intrinsicMatrixReferenceDimensions

            let rw = CGFloat(ref.width),  rh = CGFloat(ref.height)
            let w  = rgbSize.width,       h  = rgbSize.height

            let kxx = CGFloat(K[0,0])   // fx in ref space (pixels)
            let kyy = CGFloat(K[1,1])   // fy in ref space (pixels)

            // If aspect matches → same orientation; if matches swapped → 90° rotation
            let eps: CGFloat = 0.02
            let sameAspect    = abs((w/h) - (rw/rh)) < eps
            let swappedAspect = abs((w/h) - (rh/rw)) < eps

            let fx, fy: CGFloat
            if sameAspect {
                // X→X, Y→Y
                fx = kxx * (w / rw)
                fy = kyy * (h / rh)
            } else if swappedAspect {
                // 90° rotation: ref X maps to RGB Y, ref Y maps to RGB X
                fx = kyy * (w / rh)  // RGB X from ref Y
                fy = kxx * (h / rw)  // RGB Y from ref X
            } else {
                // Fallback (letterbox/crop): choose the closest mapping
                fx = kxx * (w / rw)
                fy = kyy * (h / rh)
            }

            if fx.isFinite && fy.isFinite && fx > 0 && fy > 0 { return (fx, fy) }
        }

        // (B) CVPixelBuffer attachment (modern API): CVBufferCopyAttachment
        if let img = CMSampleBufferGetImageBuffer(sampleBuffer) {
            var mode = CVAttachmentMode.shouldPropagate
            if let any = CVBufferCopyAttachment(img, "CameraIntrinsicMatrix" as CFString, &mode),
               let data = any as? Data {
                let K  = data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
                let fx = CGFloat(K[0,0]), fy = CGFloat(K[1,1])
                if fx.isFinite && fy.isFinite && fx > 0 && fy > 0 { return (fx, fy) }
            }

            // Whole-dictionary variant (also non-deprecated)
            if let dict = CVBufferCopyAttachments(img, .shouldPropagate) as? [CFString: Any],
               let data = dict["CameraIntrinsicMatrix" as CFString] as? Data {
                let K  = data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
                let fx = CGFloat(K[0,0]), fy = CGFloat(K[1,1])
                if fx.isFinite && fy.isFinite && fx > 0 && fy > 0 { return (fx, fy) }
            }
        }

        // (C) CMFormatDescription extensions (use literal key)
        if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
           let exts = CMFormatDescriptionGetExtensions(fmt) as? [String: Any],
           let data = exts["CameraIntrinsicMatrix"] as? Data {
            let K  = data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
            let fx = CGFloat(K[0,0]), fy = CGFloat(K[1,1])
            if fx.isFinite && fy.isFinite && fx > 0 && fy > 0 { return (fx, fy) }
        }

        // (D) Legacy sample-buffer attachment (keep as last resort)
        var mode: CMAttachmentMode = 0
        if let data = CMGetAttachment(sampleBuffer,
                                      key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                      attachmentModeOut: &mode) as? Data {
            let K  = data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
            let fx = CGFloat(K[0,0]), fy = CGFloat(K[1,1])
            if fx.isFinite && fy.isFinite && fx > 0 && fy > 0 { return (fx, fy) }
        }

        return nil
    }

    private static func normalizedFxFy(_ fx: CGFloat, _ fy: CGFloat,
                        ref: CGSize?, rgbSize: CGSize) -> (CGFloat, CGFloat) {
        // If reference or attachment K was recorded in a different orientation
        // than the RGB buffer, swap axes so X maps to width, Y maps to height.
        let rgbIsPortrait = rgbSize.height > rgbSize.width
        if let ref = ref {
            let refIsPortrait = ref.height > ref.width
            if refIsPortrait != rgbIsPortrait { return (fy, fx) }
        }
        return (fx, fy)
    }
    
    
    func ringDepthMM(
        rgbRect pr: CGRect,
        rgbSize: CGSize,
        depthData ddIn: AVDepthData,
        ringPx: CGFloat = 14,          // width of the ring band in *depth pixels*
        trim: Double = 0.10,           // 10% low/high trim
        zMinM: Float = 0.12,           // 12 cm (near-limit of LiDAR)
        zMaxM: Float = 4.0             // 4 m (far-limit)
    ) -> Double? {
        // 1) Always work in DepthFloat32 (meters)
        let dd = ddIn.depthDataType == kCVPixelFormatType_DepthFloat32
               ? ddIn
               : ddIn.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)

        let dPB = dd.depthDataMap
        CVPixelBufferLockBaseAddress(dPB, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dPB, .readOnly) }

        let dw = CVPixelBufferGetWidth(dPB)
        let dh = CVPixelBufferGetHeight(dPB)
        guard let base = CVPixelBufferGetBaseAddress(dPB) else { return nil }
        let elemsPerRow = CVPixelBufferGetBytesPerRow(dPB) / MemoryLayout<Float32>.size
        let buf = base.assumingMemoryBound(to: Float32.self)

        // 2) Map RGB rect -> DEPTH rect (scale + Y flip)
        let sx = CGFloat(dw) / rgbSize.width
        let sy = CGFloat(dh) / rgbSize.height
        let rx = pr.origin.x * sx
        let rw = pr.size.width  * sx
        let rh = pr.size.height * sy
        let ry = CGFloat(dh) - (pr.origin.y * sy) - rh   // flip Y (depth = top-left)

        var R = CGRect(x: rx, y: ry, width: rw, height: rh).integral
        if R.isNull || R.width < 2 || R.height < 2 { return nil }

        // 3) Build outer-rect (inflate) and ring = outer - inner
        let pad = max(ringPx, 4)
        let outer = CGRect(
            x: max(0, R.minX - pad),
            y: max(0, R.minY - pad),
            width: min(CGFloat(dw), R.maxX + pad) - max(0, R.minX - pad),
            height: min(CGFloat(dh), R.maxY + pad) - max(0, R.minY - pad)
        ).integral

        // 4) Sample decimated grid over OUTER, skip INNER
        var zs = [Float]()
        let step = max(1, Int(min(outer.width, outer.height) / 72)) // light decimation

        let x0 = Int(outer.minX), x1 = Int(outer.maxX) - 1
        let y0 = Int(outer.minY), y1 = Int(outer.maxY) - 1
        for j in stride(from: y0, through: y1, by: step) {
            let row = buf + j * elemsPerRow
            for i in stride(from: x0, through: x1, by: step) {
                // skip inner rect (lesion area)
                if i >= Int(R.minX), i < Int(R.maxX), j >= Int(R.minY), j < Int(R.maxY) { continue }
                let z = row[i] // meters (DepthFloat32)
                if z.isFinite, z >= zMinM, z <= zMaxM { zs.append(z) }
            }
        }
        guard !zs.isEmpty else { return nil }

        // 5) Trim extremes and take median (in *meters* → convert to *mm*)
        zs.sort()
        let n = zs.count
        let k = Int((trim * Double(n)).rounded(.down))
        let kept = Array(zs.dropFirst(min(k, n - 1)).dropLast(min(k, n - 1)))
        let arr = kept.isEmpty ? zs : kept
        let mid = arr.count / 2
        let zM = arr.count % 2 == 0 ? (Double(arr[mid-1]) + Double(arr[mid])) * 0.5
                                     : Double(arr[mid])

        return zM * 1000.0
    }

}

private extension Array where Element == Float {
    var median: Float? {
        guard !isEmpty else { return nil }
        let s = sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m-1] + s[m]) * 0.5 : s[m]
    }
    
    
}
