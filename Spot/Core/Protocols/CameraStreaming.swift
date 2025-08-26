//
//  CameraStreaming.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import AVFoundation
import Combine

public protocol CameraStreaming: AnyObject {
    var frames: AnyPublisher<CMSampleBuffer, Never> { get }
    var session: AVCaptureSession { get }
    func start()
    func stop()
}
