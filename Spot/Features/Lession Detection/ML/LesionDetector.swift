//
//  FoodDetector.swift
//  Spot
//
//  Created by Hasan on 18/08/2025.
//


import CoreML
import Vision
import AVFoundation
import CoreImage
import UIKit


final class LesionDetector {
    private let request: VNCoreMLRequest
    private let mlQueue = DispatchQueue(label: "ml.queue")
    
    init() {
        let modelURL = Bundle.main.url(forResource: "ColorPatch_Detection_v2", withExtension: "mlmodelc")!
        let model = try! VNCoreMLModel(for: .init(contentsOf: modelURL))
        let req = VNCoreMLRequest(model: model)
        req.imageCropAndScaleOption = .centerCrop
        req.preferBackgroundProcessing = true
        self.request = req
    }
    
    func classify(_ pixelBuffer: CVPixelBuffer, completion: @escaping (_ best: String, _ confidence: Float) -> Void) {
        mlQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.request])
                let results = (self.request.results as? [VNRecognizedObjectObservation]) ?? []
                print("results",results.count)
                let best = results.first
                completion(best?.labels.first?.identifier ?? "Unknown", best?.confidence ?? 0)
            } catch {
                completion("Error", 0)
            }
        }
    }
    
    func classify(_ pixelBuffer: CVPixelBuffer) async -> (label: String, conf: Float) {
        await withCheckedContinuation { cont in
            classify(pixelBuffer) { l, c in cont.resume(returning: (l, c)) }
        }
    }
    
}
