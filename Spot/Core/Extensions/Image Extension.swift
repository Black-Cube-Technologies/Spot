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
