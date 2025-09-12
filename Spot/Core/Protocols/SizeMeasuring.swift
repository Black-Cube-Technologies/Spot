//
//  SizeMeasuring.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//
import Vision
import CoreGraphics

public protocol SizeMeasuring {
    func measure(from obs: VNRecognizedObjectObservation,
                 pixelBuffer pb: CVPixelBuffer,
                 visionOrientation: CGImagePropertyOrientation,
                 calib: PixelCalibration,
                 fillRatio: CGFloat) -> LesionMeasurement

    func format(_ m: LesionMeasurement, units: UnitSystem, decimals: Int) -> String
}
