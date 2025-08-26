//
//  UnitSystem.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import CoreGraphics

public enum UnitSystem { case metric, imperial }

public struct PixelCalibration {
    public let mmPerPixelX: CGFloat
    public let mmPerPixelY: CGFloat
    public init(mmPerPixel: CGFloat) { self.mmPerPixelX = mmPerPixel; self.mmPerPixelY = mmPerPixel }
    public init(mmPerPixelX: CGFloat, mmPerPixelY: CGFloat) { self.mmPerPixelX = mmPerPixelX; self.mmPerPixelY = mmPerPixelY }
}

public struct LesionMeasurement {
    public let bboxNorm: CGRect      // Vision normalized rect [0,1], origin bottom-left
    public let pixelRect: CGRect     // image pixels, top-left origin
    public let widthMM: CGFloat
    public let heightMM: CGFloat
    public let areaMM2: CGFloat
    public let equivDiameterMM: CGFloat
}
