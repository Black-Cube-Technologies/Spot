//
//  LesionDetecting.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import Vision
import CoreVideo

public protocol LesionDetecting: AnyObject {
    /// Async so ViewModel stays simple & testable
    func detect(in pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation) async -> [LesionModel]
}
