import SwiftUI
import AVFoundation

struct LesionView: View {
    @StateObject private var vm: LesionViewModel
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var calPoints: [CGPoint] = []

    init(camera: CameraStreaming, detector: LesionDetecting) {
        _vm = StateObject(wrappedValue: LesionViewModel(camera: camera, detector: detector))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: vm.session, vm: vm, previewLayer: $previewLayer)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { location in
                    calPoints.append(location)
                    if calPoints.count == 2, let pl = previewLayer {
                        vm.calibrate(knownMM: 10, // e.g. 10 mm sticker/ruler
                                     p1InPreview: calPoints[0],
                                     p2InPreview: calPoints[1],
                                     previewLayer: pl)
                        calPoints.removeAll()
                    }
                }

            if !vm.boxNorm.isNull {
                BoxOverlay(norm: vm.boxNorm).ignoresSafeArea()
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
            .padding(.bottom, 24)
        }
        .onAppear {
            vm.start()
        }
        .onDisappear { vm.stop() }
    }
}
