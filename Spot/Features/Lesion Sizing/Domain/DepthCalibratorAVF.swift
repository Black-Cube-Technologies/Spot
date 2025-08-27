// DepthCalibratorAVF.swift
import AVFoundation
import Vision
import simd
import CoreVideo

public enum DepthCalibratorAVF {
    /// Returns mm/px for X,Y using Z (meters) and intrinsics (fx, fy).
    /// - Parameters:
    ///   - sampleBuffer: RGB buffer with kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix
    ///   - depthData: optional depth; if nil returns nil
    ///   - roiNorm: lesion bbox in **Vision normalized** coords (0..1)
    /// - Note: Uses median Z inside ROI for robustness; converts to mm.
    public static func calibration(for sampleBuffer: CMSampleBuffer,
                                   depthData inDepth: AVDepthData?,
                                   roiNorm: CGRect) -> PixelCalibration? {
        guard let depthData = inDepth else { return nil }
        // 1) Intrinsics (fx, fy)
        var mode: CMAttachmentMode = 0
        guard let data = CMGetAttachment(sampleBuffer,
                                         key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                         attachmentModeOut: &mode) as? Data else { return nil }
        let K = data.withUnsafeBytes { $0.load(as: simd_float3x3.self) }
        let fx = CGFloat(K[0,0])
        let fy = CGFloat(K[1,1])

        // 2) ROI in video pixels
        guard let img = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let iw = CGFloat(CVPixelBufferGetWidth(img))
        let ih = CGFloat(CVPixelBufferGetHeight(img))
        let roiPx = VNImageRectForNormalizedRect(roiNorm, Int(iw), Int(ih))

        // 3) Map ROI to depth map resolution
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
        let ptr    = unsafeBitCast(CVPixelBufferGetBaseAddress(dm), to: UnsafePointer<Float32>.self)

        // 4) Collect median Z (meters) with sub-sampling for speed
        var zs: [Float] = []
        let x0 = max(0, Int(rD.minX)), x1 = min(Int(dw)-1, Int(rD.maxX))
        let y0 = max(0, Int(rD.minY)), y1 = min(Int(dh)-1, Int(rD.maxY))
        var y = y0
        while y <= y1 {
            let row = ptr + y*stride
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

        // 5) mm/px from Z and intrinsics
        return PixelCalibration(mmPerPixelX: zMM / fx,
                                mmPerPixelY: zMM / fy)
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
