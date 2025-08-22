//
//  SpotTests.swift
//  SpotTests
//
//  Created by Hasan on 18/08/2025.
//

import Testing
@testable import Spot
import CoreML
import Vision
import UIKit
struct SpotTests {
    
    struct LesionDetectorTests {
        
        private let detector = LesionDetector()
        
        @Test func passing_accuracy_is_above_threshold() async throws {
            let fixtures = try loadLesionImages()
            try! #require(!fixtures.isEmpty, "No images in images.json")
            
            var correct = 0
            var total = 0
            var confidences: [Float] = []
            
            for fx in fixtures {
                let imgURL = TestRes.url((fx.image as NSString).deletingPathExtension,
                                         (fx.image as NSString).pathExtension.isEmpty ? nil : (fx.image as NSString).pathExtension)
                guard let ui = UIImage(contentsOfFile: imgURL.path),
                      let cg = ui.cgImage,
                      let pb = makePixelBuffer(from: cg) else {
                    Issue.record("Could not load/convert \(fx.image)")
                    continue
                }
                
                let (pred, conf) = await detector.classify(pb)
                total += 1
                confidences.append(conf)
                if pred == fx.label { correct += 1 }
            }
            
            let acc = Double(correct) / Double(max(total, 1))
            print("Passing accuracy: \(acc), N=\(total), mean conf: \(confidences.reduce(0,+)/Float(max(total,1)))")
            
            // ✅ Gate the build with a threshold you’re comfortable with
            #expect(acc >= TestConstants.desiredDetectionPassingAccuracy, "Passing accuracy below threshold (acc=\(acc))")
        }
        
        
        @Test func mean_confidence_is_reasonable() async throws {
            let fixtures = try loadLesionImages()
            
            var confs: [Float] = []
            for fx in fixtures {
                let url = TestRes.url((fx.image as NSString).deletingPathExtension,
                                      (fx.image as NSString).pathExtension.isEmpty ? nil : (fx.image as NSString).pathExtension)
                guard let ui = UIImage(contentsOfFile: url.path),
                      let cg = ui.cgImage,
                      let pb = makePixelBuffer(from: cg) else { continue }
                
                let (pred, conf) = await detector.classify(pb)
                if pred == fx.label { confs.append(conf) }
            }
            
            let mean = Double(confs.reduce(0, +) / Float(max(confs.count, 1)))
            print("Mean confidence on correct preds: \(mean)")
            #expect(mean >= TestConstants.desiredDetectionMeanConfidence)
        }
        
        @Test func false_positives_is_below_threshold() async throws {
            let fixtures = try loadHealthyImages()
            try! #require(!fixtures.isEmpty, "No images in healthy.json")
            
            var falsePositive = 0
            var total = 0
            var confidences: [Float] = []
            
            for fx in fixtures {
                let imgURL = TestRes.url((fx.image as NSString).deletingPathExtension,
                                         (fx.image as NSString).pathExtension.isEmpty ? nil : (fx.image as NSString).pathExtension)
                guard let ui = UIImage(contentsOfFile: imgURL.path),
                      let cg = ui.cgImage,
                      let pb = makePixelBuffer(from: cg) else {
                    Issue.record("Could not load/convert \(fx.image)")
                    continue
                }
                
                let (pred, conf) = await detector.classify(pb)
                print("false positive label",pred)
                total += 1
                confidences.append(conf)
                if pred == TestConstants.lesionLabel { falsePositive += 1 }
            }
            
            let acc = Double(falsePositive) / Double(max(total, 1))
            print("False positive accuracy: \(falsePositive) \(acc), N=\(total), mean conf: \(confidences.reduce(0,+)/Float(max(total,1)))")
            
            // ✅ Gate the build with a threshold you’re comfortable with
            #expect(acc <= TestConstants.desiredFalsePositiveThreshold, "False positive accuracy below threshold (acc=\(acc))")
        }
    }
    
    struct LesionMeasuringTests {
        
        private let measure = LesionMeasure()
        
        @Test func measuring_accuracy_is_above_threshold() async throws {
            let fixtures = try loadLesionImages()
            
            var correct = 0
            var total = 0
            for fx in fixtures {
                let url = TestRes.url((fx.image as NSString).deletingPathExtension,
                                      (fx.image as NSString).pathExtension.isEmpty ? nil : (fx.image as NSString).pathExtension)
                guard let ui = UIImage(contentsOfFile: url.path),
                      let cg = ui.cgImage,
                      let _ = makePixelBuffer(from: cg) else { continue }
                total += 1
                let size =  measure.measureLesion()
                if abs(size - fx.size) <= LesionConstants.sizeMargin { correct += 1}
            }
            
            let acc = Double(correct) / Double(max(total, 1))
            print("Passing accuracy: \(acc)")
            #expect(acc >= TestConstants.desiredMeasureAccuracy)
        }
    }
}
