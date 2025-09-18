import Vision
import CoreML
import AVFoundation

public final class LesionDetector: LesionDetecting {
    
    public var smallModelRequest: VNCoreMLRequest
    private let smallThreshold: Float = 0.2
    
    public var largeModelRequest: VNCoreMLRequest
    private let largeThreshold: Float = 0.4 // fixed
    
    public init() {
        do {
            self.largeModelRequest = try Self.loadRequest(filename: LesionConstants.largeMLModelName)
            self.smallModelRequest = try Self.loadRequest(filename: LesionConstants.smallMLModelName)
        }
        catch {
            fatalError("Failed to initialise Lesion Detector: \(error)")
        }
    }
    
    private static func loadRequest(filename: String) throws -> VNCoreMLRequest {
        
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mlmodelc") else {
            throw NSError.getError(description: "Unable to load MLModel File \(filename)")
        }
        
        let file = try MLModel(contentsOf: url)
        
        let model = try VNCoreMLModel(for: file)
        
        let request = VNCoreMLRequest(model: model)
        request.preferBackgroundProcessing = true
        
        return request
    }
    
    public func bestDetect(in pixelBuffer: CVPixelBuffer,
                           orientation: CGImagePropertyOrientation = .up) async -> (label: String, conf: Float) {
        let largeResults = await self.detectLarge(in: pixelBuffer, orientation: orientation)
        guard let largeBest = largeResults.max(by: { $0.confidence > $1.confidence }) else {
            return ("Unknown", 0)
        }
        let best = largeBest
        return (best.labels.first?.identifier ?? "Unknown", best.confidence)
            
//            print("small Results",smallResults.count)
            
//            guard let smallBest = smallResults.max(by: { $0.confidence > $1.confidence }),
//            let best = smallBest.confidence > largeBest.confidence ? smallBest : largeBest
    }
    
    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> [LesionModel] {
        
        let largeResults = await self.detectLarge(in: pixelBuffer, orientation: orientation)
            .map({ LesionModel(object: $0, type: .large) })
        //let maxLarge = largeResults.max(by: { $0.object.confidence > $1.object.confidence })?.object.confidence ?? 0.0
        
        
//        let smallResults = await self.detectSmall(in: pixelBuffer, orientation: orientation)
//            .map({ LesionModel(object: $0, type: .small) })
//        let maxSmall = smallResults.max(by: { $0.object.confidence > $1.object.confidence })?.object.confidence ?? 0.0
         
        let best = largeResults // maxLarge > maxSmall ? largeResults : smallResults
        
        // guard with large model lesions, otherewise fallback to small one (pimples, spots etc)
//        guard !largeResult.isEmpty else {
//            return smallResults
//        }
        
//        let finalResults = (largeResult + smallResults)
//            return smallResults
//        }
        return best
//        return finalResults
    }
    
    private func detectSmall(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> [VNRecognizedObjectObservation] {
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([self.smallModelRequest])
            let rawResults = (self.smallModelRequest.results as? [VNRecognizedObjectObservation]) ?? []
            let results = rawResults.filter({ $0.confidence >= smallThreshold })
//            print(results.isEmpty ? "" : "Small Lesions Results: \(results.count)")
            results.forEach({ print("Small Lesion Confidence: \(String(format: "%.5f", $0.confidence))") })
            return results
        }
        catch {
            return []
        }
    }
    
    private func detectLarge(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> [VNRecognizedObjectObservation] {
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([self.largeModelRequest])
            let rawResults = (self.largeModelRequest.results as? [VNRecognizedObjectObservation]) ?? []
            print("rawResults",rawResults.map({"\($0.labels.first!.identifier): \(String(format: "%.5f", $0.confidence))"}))
            let results = rawResults.filter({ $0.confidence >= largeThreshold })
//            print(results.isEmpty ? "" : "Large Lesion Results: \(results.count)")
            return results
        }
        catch {
            return []
        }
    }
    
    
}
