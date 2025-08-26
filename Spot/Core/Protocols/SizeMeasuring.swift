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
                 imageSize: CGSize,
                 calib: PixelCalibration,
                 fillRatio: CGFloat) -> LesionMeasurement

    func format(_ m: LesionMeasurement, units: UnitSystem, decimals: Int) -> String
}
