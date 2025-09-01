//
//  LesionResultViewModel.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
public final class LesionResultViewModel: ObservableObject {
    // Input
    @Published public private(set) var lesion: Lesion
    
    // Output
    @Published public private(set) var image: UIImage?
    @Published public var unit: DisplayUnit = .mm
    
    // Services
    private let imageStore: TempImageStoring
    
    // MARK: - Init
    public init(
        lesion: Lesion,
        imageStore: TempImageStoring
    ) {
        self.lesion = lesion
        self.imageStore = imageStore
    }
    
    // MARK: - Lifecycle
    public func onAppear() {
        loadImageFromDisk()
    }
    
    // MARK: - Computed display
    public var widthText: String  { formatLength(lesion.width) }
    public var heightText: String { formatLength(lesion.height) }
    public var areaText: String   { formatArea(lesion.width * lesion.height) }
    public var createdText: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: lesion.createdAt)
    }
    
    // MARK: - Commands
    public func discardTempIfNeeded() {
        // Call on cancel/done to clean the temp file
        try? imageStore.removeTemp(at: lesion.imageURL)
    }
    
    // MARK: - Private
    private func loadImageFromDisk() {
        image = UIImage(contentsOfFile: lesion.imageURL.path)
    }
    
    private func formatLength(_ mm: Double) -> String {
        switch unit {
        case .mm:
            return String(format: "%.1f mm", mm)
        case .cm:
            return String(format: "%.2f cm", mm / 10.0)
        }
    }
    
    private func formatArea(_ mm2: Double) -> String {
        switch unit {
        case .mm:
            return String(format: "%.0f mm²", mm2)
        case .cm:
            return String(format: "%.2f cm²", mm2 / 100.0)
        }
    }
}

// MARK: - DisplayUnit
public enum DisplayUnit: Hashable {
    case mm, cm
}
