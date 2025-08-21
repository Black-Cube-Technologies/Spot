//
//  Detection.swift
//  Spot
//
//  Created by Hasan on 18/08/2025.
//


import Foundation
import CoreGraphics

public struct Detection: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let confidence: Float
    /// Normalized rect in Vision coords (origin bottom-left, [0,1] space)
    public let boundingBox: CGRect
}
