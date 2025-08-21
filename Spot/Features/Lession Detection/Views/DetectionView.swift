import SwiftUI

struct DetectionView: View {
    @StateObject private var vm = DetectionViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: vm.session)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Text(vm.prediction).font(.title2).bold()
                Text(String(format: "Confidence: %.0f%%", vm.confidence * 100))
                    .font(.subheadline).opacity(0.8)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 24)
        }
        .onAppear { vm.requestAndStart() }
        .onDisappear { vm.stop() }
    }
}
