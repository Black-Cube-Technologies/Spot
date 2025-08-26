//
//  DetectedBox.swift
//  Spot
//
//  Created by Hasan on 27/08/2025.
//

import CoreGraphics

public struct DetectedBox: Sendable {
    public let rectNorm: CGRect   // [0,1] origin bottom-left (Vision style)
    public let label: String
    public let confidence: Float
}
