//
//  CalibrationProviding.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//
import AVFoundation
import CoreGraphics

public protocol CalibrationProviding {
    func mmPerPixel(knownMM: CGFloat,
                    p1InPreview: CGPoint, p2InPreview: CGPoint,
                    imageSize: CGSize,
                    previewLayer: AVCaptureVideoPreviewLayer) -> CGFloat
}
