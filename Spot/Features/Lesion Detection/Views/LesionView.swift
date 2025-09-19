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
            CircularCameraPreview(vm: vm)
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
            // Bottom HUD: size/units + three zoom presets
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    zoomPresetButton(title: "1×", targetZoom: 2.0) { vm.setPresetZoom1x() }
                    zoomPresetButton(title: "2×", targetZoom: 6.0) { vm.setPresetZoom2x() }
                    zoomPresetButton(title: "3×", targetZoom: 10.0) { vm.setPresetZoom3x() }
                }
                
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
    
    // MARK: - Zoom Preset Button Helper
    private func zoomPresetButton(title: String, targetZoom: CGFloat, action: @escaping () -> Void) -> some View {
        let selected = isZoomSelected(targetZoom)
        return Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showZoomOverlay(); scheduleHideZoomOverlay()
        }) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(selected ? Color.white : Color.white.opacity(0.15))
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(selected ? 0.0 : 0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(selected ? 0.25 : 0.0), radius: selected ? 6 : 0, x: 0, y: 2)
        .accessibilityLabel(Text("Zoom \(title)"))
    }
    
    private func isZoomSelected(_ target: CGFloat) -> Bool {
        // Allow a small tolerance because device zoom may clamp/ramp
        abs(vm.zoom - target) < 0.35
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

