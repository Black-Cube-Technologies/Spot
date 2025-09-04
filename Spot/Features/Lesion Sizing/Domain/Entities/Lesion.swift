//
//  Lesion.swift
//  Spot
//
//  Created by Hasan on 31/08/2025.
//import Foundation
import Foundation


public struct Lesion: Identifiable, Codable, Hashable {
    public let id: UUID
    public var width: CGFloat
    public var height: CGFloat
    public var imageURL: URL
    public var createdAt: Date
    public var boundedBoxes: [CGRect]
    
    public init(
        id: UUID = UUID(),
        width: CGFloat,
        height: CGFloat,
        imageURL: URL,
        createdAt: Date = Date(),
        boundedBoxes: [CGRect]
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.boundedBoxes = boundedBoxes
    }
    
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (l: Lesion, r: Lesion) -> Bool { l.id == r.id }
}
