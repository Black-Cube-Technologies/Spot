//
//  CameraStreaming.swift
//  Spot
//
//  Created by Hasan on 26/08/2025.
//


import AVFoundation
import Combine

public protocol CameraStreaming: AnyObject {
    var frames: AnyPublisher<FramePack, Never> { get }
    var session: AVCaptureSession { get }
    func start()
    func stop()
    func getCameraDevice() -> AVCaptureDevice?
}

public struct FramePack { // Added
    public let sampleBuffer: CMSampleBuffer   // RGB frame
    public let depthData: AVDepthData?        // nil if no depth for this frame
    public init(sampleBuffer: CMSampleBuffer, depthData: AVDepthData?) {
        self.sampleBuffer = sampleBuffer
        self.depthData = depthData
    }
}
