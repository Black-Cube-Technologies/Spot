//
//  CameraZoomControlling.swift
//  Spot
//
//  Created by Hasan on 11/09/2025.
//

import AVFoundation
import Combine

public protocol CameraZoomControlling: AnyObject {
    var minZoomFactor: CGFloat { get }
    var maxZoomFactor: CGFloat { get }
    var switchOverFactors: [CGFloat] { get } // e.g. [0.5, 1.0, 2.0]
    var currentZoom: AnyPublisher<CGFloat, Never> { get }
    func setZoom(_ factor: CGFloat, animated: Bool, rate: Float)
    func cancelZoomRamp()
}
