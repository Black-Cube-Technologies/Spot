//
//  RoboflowAPI.swift
//  Spot
//
//  Created by Hamza Hashmi on 03/09/2025.
//

import UIKit

struct ExampleResponse: Codable {
    
}

class RoboflowAPI {
    
    private let client = APIClient()
    
    func prcessImage(image: UIImage) async throws -> ExampleResponse {
        // Load Image and Convert to Base64
//        let image = UIImage(named: "your-image-path") // path to image to upload ex: image.jpg
        guard let imageData = image.jpegData(compressionQuality: 1) else {
            throw NSError.getError(description: "Error converting image to data")
        }
        
        let fileContent = imageData.base64EncodedString()
        
        guard let postData = fileContent.data(using: .utf8) else {
            throw NSError.getError(description: "Error converting base64 to data")
        }
        
        let response: ExampleResponse = try await client.post(body: postData, filename: "filename.jpg")
        
        return response
    }
}
