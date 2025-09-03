//
//  Error.swift
//  Spot
//
//  Created by Hamza Hashmi on 03/09/2025.
//

import Foundation

extension NSError {
    static func getError(domain: String = "", code: Int = -1, description: String) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey : description])
    }
}
