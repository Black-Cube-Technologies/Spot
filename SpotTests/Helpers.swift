//
//  Fixture.swift
//  Spot
//
//  Created by Hasan on 21/08/2025.
//


// Tests/SpotTests/Helpers.swift
import Foundation
import CoreImage
import CoreVideo
import UIKit

struct Fixture: Decodable {
    let image: String
    let label: String
}

enum TestRes {
    static func url(_ name: String, _ ext: String?) -> URL {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: ext)!
        #else
        return Bundle(for: DummyClass.self).url(forResource: name, withExtension: ext)!
        #endif
    }
    private final class DummyClass {}
}

func loadImages() throws -> [Fixture] {
    let url = TestRes.url("images", "json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([Fixture].self, from: data)
}

// Fast BGRA pixel buffer from CGImage
func makePixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
    let width = cgImage.width
    let height = cgImage.height
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    var pb: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault,
                              width, height,
                              kCVPixelFormatType_32BGRA,
                              attrs as CFDictionary, &pb) == kCVReturnSuccess,
          let pixelBuffer = pb
    else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                              width: width, height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                       | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }

    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelBuffer
}
