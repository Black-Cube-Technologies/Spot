//
//  Image Extension.swift
//  Spot
//
//  Created by Hasan on 11/09/2025.
//

import Foundation
import UIKit
extension UIImage {
    /// Returns a new image with pixels drawn upright (`.up`), no EXIF orientation.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }

        // Use original pixel size in points; draw respects the current orientation.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale  = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
        return img
    }
}


import UIKit

extension UIImage {
    /// Which normalized coordinate space your rect is in
    /// - `.topLeft`  : (0,0) at top-left (UIKit convention for many UIs)
    /// - `.bottomLeft`: (0,0) at bottom-left (Vision's normalized rects)
    enum NormalizedSpace { case topLeft, bottomLeft }

    /// Crop using a normalized rect (x, y, w, h in 0...1)
    /// - Parameters:
    ///   - rect01: normalized CGRect (x, y, width, height), each in 0...1
    ///   - space: coordinate origin location (top-left or bottom-left)
    /// - Returns: Cropped UIImage or nil if cropping fails
    func cropped(normalized rect01: CGRect, space: NormalizedSpace = .topLeft) -> UIImage? {
        // 1) Normalize orientation: render to .up so pixel math is reliable
        guard let base = self.normalizedUpCGImage() else { return nil }
        let imgW = CGFloat(base.width)
        let imgH = CGFloat(base.height)

        // 2) Clamp rect to [0,1] and convert Y if needed
        let clamped = rect01.clamped01()
        let y01 = (space == .bottomLeft) ? (1.0 - clamped.origin.y - clamped.size.height) : clamped.origin.y

        // 3) Convert to pixel space (align to integral pixels)
        var cropPx = CGRect(
            x: clamped.origin.x * imgW,
            y: y01 * imgH,
            width: clamped.size.width * imgW,
            height: clamped.size.height * imgH
        ).integral

        // 4) Intersect with image bounds just in case
        let boundsPx = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        cropPx = cropPx.intersection(boundsPx)
        guard cropPx.width > 0, cropPx.height > 0 else { return nil }

        // 5) Crop and wrap back to UIImage
        guard let cgCropped = base.cropping(to: cropPx) else { return nil }
        // Orientation is .up after normalization; keep scale = 1 to avoid rescaling metadata
        return UIImage(cgImage: cgCropped, scale: 1, orientation: .up)
    }

    /// Render the image into an .up-oriented CGImage (handles camera/exif orientation)
    private func normalizedUpCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = self.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // work in pixel units; we'll manage scale ourselves
        let sizePx = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: sizePx, format: format)
        let img = renderer.image { _ in
            // Draw respecting orientation by using UIKit's draw(in:)
            self.draw(in: CGRect(origin: .zero, size: sizePx))
        }
        return img.cgImage
    }
}

private extension CGRect {
    /// Clamp a normalized rect so it stays within [0,1] in both axes
    func clamped01() -> CGRect {
        let x = max(0, min(1, origin.x))
        let y = max(0, min(1, origin.y))
        let w = max(0, min(1 - x, size.width))
        let h = max(0, min(1 - y, size.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}


extension UIImage {
    /// Returns a new image rotated by the given degrees around its center.
    /// The resulting image is rendered with an `.up` orientation and preserves the original scale.
    /// - Parameter degrees: Rotation in degrees. Positive values rotate counter-clockwise.
    /// - Returns: A new rotated UIImage.
    func rotated(byDegrees degrees: CGFloat) -> UIImage {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized == 0 { return self }

        let radians = normalized * .pi / 180
        // Compute the size of the rotated bounding box
        let originalSize = self.size
        let rect = CGRect(origin: .zero, size: originalSize)
        let rotatedRect = rect.applying(CGAffineTransform(rotationAngle: radians))
        let outSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // Move origin to the center of the output image
            cg.translateBy(x: outSize.width / 2, y: outSize.height / 2)
            cg.rotate(by: radians)
            // Draw the original image centered
            self.draw(in: CGRect(x: -originalSize.width / 2,
                                 y: -originalSize.height / 2,
                                 width: originalSize.width,
                                 height: originalSize.height))
        }
        return img
    }
}
