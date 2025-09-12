// LesionView.swift (replace the bottom HUD and remove any preset pills/labels)

import SwiftUI
import AVFoundation

struct LesionView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var vm: LesionViewModel
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var calPoints: [CGPoint] = []
    
    // Pinch state
    @State private var pinchBaseZoom: CGFloat = 1.0
    
    // Zoom HUD
    @State private var showZoomHUD = false
    @State private var hudScale: CGFloat = 0.9
    @State private var hudOpacity: CGFloat = 0.0
    @State private var hudHideWorkItem: DispatchWorkItem?
    
    init(camera: CameraStreaming, detector: LesionDetecting) {
        _vm = StateObject(wrappedValue: LesionViewModel(camera: camera, detector: detector))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            // Camera + pinch (no preset taps)
            CameraPreview(session: vm.session, vm: vm, previewLayer: $previewLayer)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let target = clamp(pinchBaseZoom * scale, vm.zoomMin, vm.zoomMax)
                            vm.setZoom(target, animated: false) // pinch = direct, HUD visible
                            showZoomOverlay()
                        }
                        .onEnded { _ in
                            pinchBaseZoom = vm.zoom
                            scheduleHideZoomOverlay()
                        }
                )
                .onTapGesture { location in
                    // keep your two-tap calibration
                    calPoints.append(location)
                    if calPoints.count == 2, let pl = previewLayer {
                        vm.calibrate(knownMM: 10, p1InPreview: calPoints[0], p2InPreview: calPoints[1], previewLayer: pl)
                        calPoints.removeAll()
                    }
                }
                .onAppear { pinchBaseZoom = vm.zoom }
            
            if !vm.boxNorms.isEmpty {
                ForEach(vm.boxNorms.indices, id: \.self) { index in
                    let box = vm.boxNorms[index]
                    BoxOverlay(
                        color: box.type == .small ? .green : .red,
                        norm: box.normBox
                    )
                    .ignoresSafeArea()
                }
            }
            // Bottom HUD: size/units + single zoom button
            VStack(spacing: 14) {
                
                zoomButton
                
                HStack(spacing: 12) {
                    Text(vm.sizeText)
                        .font(.headline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    
                    Picker("", selection: $vm.units) {
                        Text("cm").tag(UnitSystem.metric)
                        Text("in").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.lesion) { draft in
            guard let lesion = draft else { return }
            vm.stop()
            Router.shared.push(.lesionResult(lesion))
        }
        .toast($vm.toastMessage)
    }
    
    // MARK: - Single Zoom Button
    private var zoomButton: some View {
        // Build without Button() to control tap vs long-press precisely
        let tap = TapGesture().onEnded {
            vm.zoomIn(animated: true)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showZoomOverlay(); scheduleHideZoomOverlay()
        }
        
        return Image(systemName: vm.zoom == vm.zoomMax ? "minus.magnifyingglass" : "plus.magnifyingglass")
            .font(.system(size: 16, weight: .semibold))
            .padding()
            .contentShape(Rectangle())
            .background(.ultraThinMaterial, in: Capsule())
            .gesture(tap)
        
    }
    
    // MARK: HUD helpers
    private func showZoomOverlay() {
        hudHideWorkItem?.cancel()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
            showZoomHUD = true; hudScale = 1.0; hudOpacity = 1.0
        }
    }
    private func scheduleHideZoomOverlay() {
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                hudOpacity = 0.0; hudScale = 0.96
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { showZoomHUD = false }
        }
        hudHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    
    private func zoomLabel(_ z: CGFloat) -> String {
        let rounded = (z * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.001 { return "\(Int(rounded))×" }
        return String(format: "%.1f×", rounded)
    }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(v, hi)) }
}
