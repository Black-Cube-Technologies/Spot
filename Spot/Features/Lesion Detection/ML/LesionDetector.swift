import Vision
import CoreML
import AVFoundation

public final class LesionDetector: LesionDetecting {
    private let request: VNCoreMLRequest
    private let q = DispatchQueue(label: "ml.detector.serial")

    public init() {
        let url = Bundle.main.url(forResource: "Lesion_Detection_V2", withExtension: "mlmodelc")!
        let ml = try! MLModel(contentsOf: url)
        let vn = try! VNCoreMLModel(for: ml)
        let req = VNCoreMLRequest(model: vn)
        req.imageCropAndScaleOption = .scaleFill
        req.preferBackgroundProcessing = true
        self.request = req
    }

    public func detect(in pixelBuffer: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation = .up) async -> [VNRecognizedObjectObservation] {
        await withCheckedContinuation { cont in
            q.async {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
                do {
                    try handler.perform([self.request])
                    cont.resume(returning: (self.request.results as? [VNRecognizedObjectObservation]) ?? [])
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }
    
    public func bestDetect(in pixelBuffer: CVPixelBuffer,
                           orientation: CGImagePropertyOrientation = .up) async -> (label: String, conf: Float) {
        await withCheckedContinuation { cont in
            q.async {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
                do {
                    try handler.perform([self.request])
                    let results = (self.request.results as? [VNRecognizedObjectObservation]) ?? []
                    print("results",results.count)
                    let best = results.first
                    cont.resume(returning:  (best?.labels.first?.identifier ?? "Unknown", best?.confidence ?? 0))
                } catch {
                    cont.resume(returning: ("Error", 0))
                }
            }
        }
    }
    
}
