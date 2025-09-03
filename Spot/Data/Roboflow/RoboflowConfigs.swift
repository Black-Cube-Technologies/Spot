//
//  RoboflowConfigs.swift
//  Spot
//
//  Created by Hamza Hashmi on 03/09/2025.
//

import Foundation

struct RoboflowConfigs {
    static var baseURL = {
        guard let hosting = Bundle.main.infoDictionary?["ROBOFLOW_HOSTING"] as? String else {
            fatalError("Roboflow Base Hosting Missing from App Bundle or Configuration file")
        }
        let urlString = "https://" + hosting
        
        guard let url = URL(string: urlString) else {
            fatalError("Invalid URL for Roboflow")
        }
        return url
    }()
    
    static var apiKey = {
        guard let key = Bundle.main.infoDictionary?["ROBOFLOW_API_KEY"] as? String else {
            fatalError("Roboflow APIKey is Missing from App Bundle or Configuration file")
        }
        return key
    }()
}
