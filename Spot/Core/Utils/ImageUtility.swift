//
//  ImageUtility.swift
//  Spot
//
//  Created by Hasan on 31/08/2025.
//

import UIKit
import CoreImage
import CoreMedia
class ImageUtility{
    static func uiImage(from sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation = .up) -> UIImage? {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pb)
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
    }
    
    
    
    
}
