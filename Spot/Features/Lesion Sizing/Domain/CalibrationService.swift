//
//  CalibrationProviding.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import AVFoundation
import CoreGraphics

public final class CalibrationService: CalibrationProviding {
    public init() {}

    public func mmPerPixel(knownMM: CGFloat,
                           p1InPreview: CGPoint, p2InPreview: CGPoint,
                           imageSize: CGSize,
                           previewLayer: AVCaptureVideoPreviewLayer) -> CGFloat {

        // Map preview points → capture device normalized → image pixels
        let d1 = previewLayer.captureDevicePointConverted(fromLayerPoint: p1InPreview)
        let d2 = previewLayer.captureDevicePointConverted(fromLayerPoint: p2InPreview)

        let a = CGPoint(x: d1.x * imageSize.width, y: d1.y * imageSize.height)
        let b = CGPoint(x: d2.x * imageSize.width, y: d2.y * imageSize.height)

        let pix = max(1, hypot(a.x - b.x, a.y - b.y))
        return knownMM / pix
    }
}
