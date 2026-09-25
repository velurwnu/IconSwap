import AppKit
import Foundation

/// Disk cache for search-result thumbnails (lowResPngUrl), keyed by objectID.
actor PreviewCache {
    static let shared = PreviewCache()
    private let session = URLSession.shared
    private var inFlight: [String: Task<NSImage, Error>] = [:]

    /// A freshly rendered grid fires dozens of thumbnail requests at once,
    /// which alone is enough to trip the CDN's rate limit; capping how many
    /// run concurrently keeps normal browsing under that threshold.
    private let maxConcurrentFetches = 4
    private var activeFetches = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func cachedFileURL(for objectID: String) -> URL {
        Paths.previewCache.appendingPathComponent("\(objectID).png")
    }

    private func acquireFetchSlot() async {
        if activeFetches < maxConcurrentFetches {
            activeFetches += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        activeFetches += 1
    }

    private func releaseFetchSlot() {
        activeFetches -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
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
            let data = try await fetchImageData(from: remoteURL)
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

    /// Retries 429s (honoring Retry-After when present) instead of leaving
    /// the cell stuck loading; a touch of jitter keeps retries of requests
    /// that started together from re-colliding on the same instant.
    private func fetchImageData(from url: URL) async throws -> Data {
        await acquireFetchSlot()
        defer { releaseFetchSlot() }
        let maxRetries = 3
        var attempt = 0
        while true {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                return data
            }
            if http.statusCode == 429, attempt < maxRetries {
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let jitter = Double.random(in: 0...0.5)
                let delay = (retryAfter ?? pow(2.0, Double(attempt))) + jitter
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw IconSwapError.invalidImage(url: url)
            }
            return data
        }
    }
}
