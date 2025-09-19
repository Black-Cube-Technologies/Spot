import Foundation
import CoreGraphics

public extension CGRect {
    /// Returns a rectangle that is twice as wide and twice as tall as the receiver,
    /// positioned so that the center remains the same. The resulting origin has a
    /// lower x and y (moved up-left in top-left coordinate systems).
    var doubledAboutCenter: CGRect {
        let newWidth = width * 2
        let newHeight = height * 2
        let newX = midX - newWidth / 2
        let newY = midY - newHeight / 2
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    /// Returns a rectangle scaled about its center by the provided factors.
    /// - Parameters:
    ///   - widthFactor: Factor to multiply the width by.
    ///   - heightFactor: Factor to multiply the height by.
    /// - Returns: A new CGRect with the same center and scaled size.
    func scaledAboutCenter(widthFactor: CGFloat, heightFactor: CGFloat) -> CGRect {
        let newWidth = width * widthFactor
        let newHeight = height * heightFactor
        let newX = midX - newWidth / 2
        let newY = midY - newHeight / 2
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }
}
