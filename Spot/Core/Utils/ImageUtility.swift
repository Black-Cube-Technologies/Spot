//
//  ImageUtility.swift
//  Spot
//
//  Created by Hasan on 31/08/2025.
//

import UIKit
import CoreImage
import CoreMedia
import AVFoundation
class ImageUtility{
    
    enum OriginSpace { case topLeft, bottomLeft }
    
    static private let ciCtx: CIContext = {
        // avoid unexpected color management when rendering to pixel buffers
        CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace:  NSNull()
        ])
    }()

    
    static func uiImage(from sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation = .up) -> UIImage? {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pb)
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
    }
    
    static func uiImage(from pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation = .up) -> UIImage? {
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
    }
    
    
    
    
    static func cropUIImage(_ image: UIImage, toNormalizedBL rBL: CGRect) -> UIImage? {
        return image.cropped(normalized: rBL, space: .bottomLeft)
    }
    
    static func makeCircularMaskedPixelBuffer(
        from pb: CVPixelBuffer,
        previewSize: CGSize,
        gravity: AVLayerVideoGravity = .resizeAspectFill,
        diameterFractionInPreview: CGFloat,
        centerInPreview01: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> CVPixelBuffer? {

        let fmt = CVPixelBufferGetPixelFormatType(pb)
        guard fmt == kCVPixelFormatType_32BGRA else { return nil }

        let iw = CGFloat(CVPixelBufferGetWidth(pb))
        let ih = CGFloat(CVPixelBufferGetHeight(pb))
        let vw = max(1, previewSize.width)
        let vh = max(1, previewSize.height)

        // --- 1) Preview scale for the chosen gravity
        let sx = vw / iw
        let sy = vh / ih
        let scale: CGFloat = {
            switch gravity {
            case .resizeAspectFill: return max(sx, sy)   // fills, crops
            case .resizeAspect: fallthrough
            case .resize: return min(sx, sy)    // fits, letterboxes
            default: return sx                           // .resize (stretch) – uncommon for camera
            }
        }()

        // Displayed image rect inside the preview (in preview points)
        let dispW = iw * scale
        let dispH = ih * scale
        let offX  = (vw - dispW) * 0.5   // negative when image overflows (aspectFill)
        let offY  = (vh - dispH) * 0.5

        // --- 2) Circle center: from preview-normalized -> image pixels
        let cx_v = centerInPreview01.x.clamped(to: 0...1) * vw
        let cy_v = centerInPreview01.y.clamped(to: 0...1) * vh
        var cx_i = (cx_v - offX) / scale
        var cy_i = (cy_v - offY) / scale
        cx_i = cx_i.clamped(to: 0...iw)
        cy_i = cy_i.clamped(to: 0...ih)

        // --- 3) Circle radius: from preview points -> image pixels
        let frac = diameterFractionInPreview.clamped(to: 0.0...1.0)
        let d_view = min(vw, vh) * frac
        let r_img  = max(0.5, (d_view * 0.5) / scale)   // divide by preview scale

        // --- 4) Build a crisp radial mask in image pixel space
        let input  = CIImage(cvPixelBuffer: pb)
        let bounds = CGRect(x: 0, y: 0, width: iw, height: ih)

        guard
            let radial = CIFilter(name: "CIRadialGradient", parameters: [
                kCIInputCenterKey: CIVector(x: cx_i, y: cy_i),
                "inputRadius0": r_img - 0.5,  // sharp edge
                "inputRadius1": r_img + 0.5,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1), // inside
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)  // outside
            ])?.outputImage?.cropped(to: bounds)
        else { return nil }

        let blackBG = CIImage(color: .black).cropped(to: bounds)
        let masked  = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blackBG,
            kCIInputMaskImageKey: radial
        ])

        // --- 5) Render to a new PB
        var outPB: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: fmt,
            kCVPixelBufferWidthKey: Int(iw),
            kCVPixelBufferHeightKey: Int(ih),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        guard CVPixelBufferCreate(nil, Int(iw), Int(ih), fmt, attrs as CFDictionary, &outPB) == kCVReturnSuccess,
              let out = outPB else { return nil }

        ciCtx.render(masked, to: out)
        return out
    }

    
    private static let ciCtxForCapture = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace:  NSNull()
    ])

    static func uiImage(from pb: CVPixelBuffer,
                        orientation exif: CGImagePropertyOrientation) -> UIImage? {
        var ci = CIImage(cvPixelBuffer: pb)
        ci = ci.oriented(exif)                   // match Vision's orientation
        guard let cg = ciCtxForCapture.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)              // baked as .up
    }
}
private extension CGFloat {
    func clamped(to r: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.minimum(r.upperBound, CGFloat.maximum(r.lowerBound, self))
    }
    func clamped01() -> CGFloat {
        CGFloat.maximum(0, CGFloat.minimum(1, self))
    }
}
