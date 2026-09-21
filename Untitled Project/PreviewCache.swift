import AppKit
import Foundation

/// Disk cache for search-result thumbnails (lowResPngUrl), keyed by objectID.
actor PreviewCache {
    static let shared = PreviewCache()
    private let session = URLSession.shared
    private var inFlight: [String: Task<NSImage, Error>] = [:]

    private func cachedFileURL(for objectID: String) -> URL {
        Paths.previewCache.appendingPathComponent("\(objectID).png")
    }

    func image(for hit: IconHit) async throws -> NSImage {
        let fileURL = cachedFileURL(for: hit.objectID)
        if let existing = NSImage(contentsOf: fileURL) {
            return existing
        }
        if let running = inFlight[hit.objectID] {
            return try await running.value
        }
        guard let remoteURL = hit.previewURL else {
            throw IconSwapError.invalidImage(url: fileURL)
        }
        let task = Task<NSImage, Error> {
            let (data, _) = try await session.data(from: remoteURL)
            try data.write(to: fileURL, options: .atomic)
            guard let image = NSImage(data: data) else {
                throw IconSwapError.invalidImage(url: remoteURL)
            }
            return image
        }
        inFlight[hit.objectID] = task
        defer { inFlight[hit.objectID] = nil }
        return try await task.value
    }
}
