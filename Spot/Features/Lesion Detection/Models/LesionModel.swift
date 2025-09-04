//
//  DetectedLesion.swift
//  Spot
//
//  Created by Hamza Hashmi on 04/09/2025.
//

import Foundation
import Vision

public struct LesionModel: Identifiable {
    public var id = UUID().uuidString
    var object: VNRecognizedObjectObservation
    var normBox: CGRect = .null
    var type: LesionType
    
    enum LesionType {
        case large
        case small
    }
    
    func copyWith(normBox: CGRect) -> LesionModel {
        return .init(
            id: id,
            object: object,
            normBox: normBox,
            type: type
        )
    }
}
