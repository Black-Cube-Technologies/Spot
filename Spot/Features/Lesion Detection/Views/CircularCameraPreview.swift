//
//  CircularCameraPreview.swift
//  Spot
//
//  Created by Hasan on 16/09/2025.
//


import SwiftUI
import AVFoundation

/// Drop-in circular camera viewport that reuses your existing `CameraPreview`.
/// - roiFraction: diameter as a fraction of the shortest screen side (0.0...1.0).
struct CircularCameraPreview: View {
    @StateObject var vm: LesionViewModel
    private let ringWidth: CGFloat = 8
    
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height) * max(0.1, min(1.0, DetectionConstants.roiFraction))
            ZStack {
                // 1) Your existing preview, but clipped to a circle
                CameraPreview(session: vm.session, vm: vm, previewLayer: $previewLayer)
                
                    .onAppear {
                        // Fill the circle so we don't see letterboxing in the round mask
                        previewLayer?.videoGravity = .resizeAspectFill
                        // Attach layer so your VM's conversions keep working
                        if let layer = previewLayer { vm.attach(previewLayer: layer) }
                    }
                //
                
                
                
                
                // 2) Dim everything outside the circle (nice vignette)
                Color.black.opacity(0.75)
                    .mask(
                        ZStack {
                            Rectangle().frame(width: geo.size.width, height: geo.size.height)
                            Circle()
                                .frame(width: d, height: d)
                                .position(x: geo.size.width/2, y: geo.size.height/2)
                                .blendMode(.destinationOut)
                        }
                    )
                    .compositingGroup()
                    .allowsHitTesting(false)
                
                
                
                
                // 3) A subtle white ring to guide centering
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: d, height: d)
                    .position(x: geo.size.width/2, y: geo.size.height/2)
                    .allowsHitTesting(false)
                
                let progress  = vm.validMeasurementValues.isEmpty ? 0 : Double(vm.validMeasurementValues.count) / Double(vm.requiredValidMeasurements)
                ProgressRing(progress: progress, lineWidth: ringWidth)
                    .frame(width: d+3, height: d+3)
                    .position(x: geo.size.width/2, y: geo.size.height/2)
                    .allowsHitTesting(false)
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
}
