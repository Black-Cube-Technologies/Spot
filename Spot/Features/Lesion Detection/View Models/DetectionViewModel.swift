import Foundation
import Combine
import AVFoundation

final class DetectionViewModel: ObservableObject {

    // UI state — write only on MainActor
    @Published private(set) var prediction: String = "—"
    @Published private(set) var confidence: Float = 0

    let camera = CameraService()
    private let detector = LesionDetector()
    private var bag = Set<AnyCancellable>()

    init() {
        camera.configure()

        // Do any throttling here instead of a lastInferenceTime property
        camera.frameSubject
            .throttle(for: .milliseconds(120), scheduler: DispatchQueue.global(), latest: true)
            .sink { [weak self] buffer in
                guard let self, let pb = CMSampleBufferGetImageBuffer(buffer) else { return }
                self.detector.classify(pb) { [weak self] label, conf in
                    guard let self else { return }
                    Task { @MainActor in
                        self.prediction = label
                        self.confidence = conf
                    }
                }
            }
            .store(in: &bag)
    }

    func requestAndStart() {
        // Completion is @Sendable; do not touch MainActor state here.
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            self.camera.start()
        }
    }

    func stop() {
        camera.stop()
    }

    // Expose for preview layer
    var session: AVCaptureSession { camera.session }
}
