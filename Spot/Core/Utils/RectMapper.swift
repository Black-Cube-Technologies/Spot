//
//  RectMapper.swift
//  Spot
//
//  Created by Hasan on 18/08/2025.
//


import CoreGraphics

struct RectMapper {
    /// Convert Vision normalized rect (origin bottom-left) into view rect respecting aspectFill.
    static func viewRect(for normalized: CGRect,
                         viewSize: CGSize,
                         contentSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              contentSize.width > 0, contentSize.height > 0 else { return .zero }

        // Convert to top-left origin normalized
        let nv = CGRect(x: normalized.minX,
                        y: 1 - normalized.origin.y - normalized.height,
                        width: normalized.width,
                        height: normalized.height)

        // AspectFill transform
        let rView = viewSize.width / viewSize.height
        let rContent = contentSize.width / contentSize.height

        var scale: CGFloat
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0

        if rContent < rView {
            // content taller; scale by width
            scale = viewSize.width / contentSize.width
            let scaledH = contentSize.height * scale
            yOffset = (viewSize.height - scaledH) * 0.5
        } else {
            // content wider; scale by height
            scale = viewSize.height / contentSize.height
            let scaledW = contentSize.width * scale
            xOffset = (viewSize.width - scaledW) * 0.5
        }

        let rect = CGRect(x: nv.minX * contentSize.width * scale + xOffset,
                          y: nv.minY * contentSize.height * scale + yOffset,
                          width: nv.width * contentSize.width * scale,
                          height: nv.height * contentSize.height * scale)
        return rect.integral
    }
}
