import Foundation
import Combine
import AVFoundation
import Vision

@MainActor
public final class LesionViewModel: ObservableObject {

    // MARK: Published UI state
    @Published public private(set) var sizeText: String = "—"
    @Published public private(set) var boxNorm: CGRect = .null
    @Published public var units: UnitSystem = .metric

    // MARK: Dependencies (protocols)
    private let camera: CameraStreaming
    private let detector: LesionDetecting
    private let measurer: SizeMeasuring
    private let calibrator: CalibrationProviding

    // MARK: Config
    private var calib = PixelCalibration(mmPerPixel: 0.10)  // set via calibration UI
    private var fillRatio: CGFloat = 0.72

    // MARK: Internals
    private var bag = Set<AnyCancellable>()
    private var lastImageSize: CGSize = .zero

    public init(camera: CameraStreaming,
                detector: LesionDetecting,
                measurer: SizeMeasuring = MeasurementService(),
                calibrator: CalibrationProviding = CalibrationService()) {
        self.camera = camera
        self.detector = detector
        self.measurer = measurer
        self.calibrator = calibrator

        camera.frames
            .compactMap { CMSampleBufferGetImageBuffer($0) }
            .throttle(for: .milliseconds(150), scheduler: DispatchQueue.global(), latest: true)
            .sink { [weak self] pb in
                guard let self else { return }
                let imSize = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
                self.lastImageSize = imSize

                Task.detached { [weak self] in
                    guard let self else { return }
                    let obs = await self.detector.detect(in: pb, orientation: .up) // pixels already rotated
                    guard let best = obs.sorted(by: { $0.confidence > $1.confidence }).first else { return }
                    let m = await self.measurer.measure(from: best, imageSize: imSize, calib: self.calib, fillRatio: self.fillRatio)
                    await MainActor.run {
                        self.boxNorm = m.bboxNorm
                        self.sizeText = self.measurer.format(m, units: self.units, decimals: 1)
                    }
                }
            }
            .store(in: &bag)
    }

    // MARK: Control
    public func start() { camera.start() }
    public func stop()  { camera.stop()  }

    public func setUnits(_ u: UnitSystem)     { units = u }
    public func setFillRatio(_ r: CGFloat)    { fillRatio = max(0, min(1, r)) }

    /// Calibrate from two taps across a known mm distance on the preview.
    public func calibrate(knownMM: CGFloat,
                          p1InPreview: CGPoint, p2InPreview: CGPoint,
                          previewLayer: AVCaptureVideoPreviewLayer) {
        guard lastImageSize != .zero else { return }
        let mmPx = calibrator.mmPerPixel(knownMM: knownMM,
                                         p1InPreview: p1InPreview, p2InPreview: p2InPreview,
                                         imageSize: lastImageSize, previewLayer: previewLayer)
        calib = PixelCalibration(mmPerPixel: mmPx)
    }

    // Expose session for preview binding
    public var session: AVCaptureSession { camera.session }
}
