//
//  APIClient.swift
//  Spot
//
//  Created by Hamza Hashmi on 03/09/2025.
//

import Foundation

final class APIClient {
    
    var baseURL = RoboflowConfigs.baseURL
    var apiKey = RoboflowConfigs.apiKey
    
    func createURLRequest(body: Data, filename: String) -> URLRequest {
        
        var url = baseURL.appending(path: "itobos-skin-lesion-detection/1")
        
        url.append(queryItems: [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "name", value: "\(filename).jpg")
        ])
        print(url.absoluteString)
//        var url = URL(string: "\(baseURL)/itobos-skin-lesion-detection/1?=\(apiKey)&name=")
        
        var request = URLRequest(url: url,timeoutInterval: 30)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = body
        return request
    }
    
    func post<T: Codable>(body: Data, filename: String) async throws -> T {
        
        // Initialize Inference Server Request with API KEY, Model, and Model Version
        let request = createURLRequest(body: body, filename: filename)
        
        // Execute Post Request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError.getError(description: "Response Invalid")
        }
        
        print(String(data: data, encoding: .utf8)!)
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NSError.getError(code: httpResponse.statusCode, description: "Invalid Request")
        }
        
        // Convert Response String to Dictionary
        do {
            let response = try JSONDecoder().decode(T.self, from: data)
            return response
//            let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        }
        catch {
            print("Response Decoding Error\(error.localizedDescription)")
            throw error
        }
    }
}
