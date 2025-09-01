//
//  TempImageStoring.swift
//  Spot
//
//  Created by Hasan on 01/09/2025.
//


// Core/Services/LocalTempImageStore.swift
import Foundation
import UIKit

public protocol TempImageStoring {
    /// Saves a JPEG into the app's Caches/Lesions directory and returns its file URL.
    func saveTempJPEG(_ image: UIImage, id: String, quality: CGFloat) throws -> URL
    /// Remove a single temp file.
    func removeTemp(at url: URL) throws
    /// Remove all temp lesion images.
    func purgeAll() throws
    /// Directory used for temp images.
    var directory: URL { get }
}

public final class LocalTempImageStore: TempImageStoring {

    public enum StoreError: LocalizedError {
        case jpegEncodingFailed
        case couldNotCreateDirectory
    }

    public let directory: URL

    public init() {
        // ~/Library/Caches/Lesions  (never backed up; OS can purge if needed)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent("Lesions", isDirectory: true)

        // create folder if missing
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                // You can propagate or assert depending on your policy
                assertionFailure("Failed to create temp image directory: \(error)")
            }
        }
    }

    public func saveTempJPEG(_ image: UIImage, id: String = UUID().uuidString, quality: CGFloat = 0.9) throws -> URL {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw StoreError.jpegEncodingFailed
        }
        let url = directory.appendingPathComponent("\(id).jpg", conformingTo: .jpeg)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func removeTemp(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func purgeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        contents.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
//
//private extension URL {
//    static var jpeg: UTType { .jpeg }
//}
