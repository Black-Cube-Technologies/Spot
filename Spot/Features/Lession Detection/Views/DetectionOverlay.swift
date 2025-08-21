//
//  DetectionOverlay.swift
//  Spot
//
//  Created by Hasan on 18/08/2025.
//


import SwiftUI

struct DetectionOverlay: View {
    let detections: [Detection]
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(detections) { det in
                    let rect = RectMapper.viewRect(for: det.boundingBox,
                                                   viewSize: geo.size,
                                                   contentSize: videoSize)

                    // Box
                    Path { p in p.addRect(rect) }
                        .stroke(lineWidth: 2)
                        .foregroundStyle(.green)
                        .shadow(radius: 2)

                    // Label
                    Text("\(det.label) \(Int(det.confidence * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .position(x: rect.midX, y: rect.minY - 12)
                }
            }
            .animation(.easeOut(duration: 0.12), value: detections.map(\.id))
        }
        .allowsHitTesting(false)
    }
}
//guard let modelURL = Bundle.main.url(forResource: modelFileName, withExtension: modelFileExtension) else {
//    throw NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey : "Model file is missing"])
//}
//
//let model = try MLModel(contentsOf: modelURL)
