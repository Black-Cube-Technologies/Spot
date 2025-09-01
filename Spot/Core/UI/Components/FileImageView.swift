//
//  FileImageView.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//


// UI/Components/FileImageView.swift
import SwiftUI

public struct FileImageView: View {
    public let url: URL
    public init(url: URL) { self.url = url }

    public var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Text("Image unavailable").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
