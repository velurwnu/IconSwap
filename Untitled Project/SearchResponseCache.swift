import Foundation

/// Persists search responses across launches. The macosicons key has a hard
/// call quota rather than a sliding rate limit, so once it's spent every
/// request 429s until the tariff window resets — results that were already
/// paid for have to survive a relaunch, otherwise browsing dies completely.
actor SearchResponseCache {
    static let shared = SearchResponseCache()

    private struct Entry: Codable {
        let storedAt: Date
        let response: IconSearchResponse
    }

    private let fileURL = Paths.searchCacheFile
    private let maxEntries = 1000
    /// The icon catalog changes slowly, so a month-old result is still good.
    private let freshAge: TimeInterval = 30 * 24 * 60 * 60
    /// Expired entries are kept this long as a fallback for when the API
    /// can't be reached or the quota is spent — stale results beat none.
    private let maxAge: TimeInterval = 180 * 24 * 60 * 60

    private var entries: [String: Entry]?

    /// Case, diacritics and extra whitespace don't change what the server
    /// returns, so "Visual  Studio" and "visual studio" share one paid call.
    static func key(query: String, page: Int) -> String {
        let normalized = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return "\(normalized)#\(page)"
    }

    func response(for key: String, allowStale: Bool = false) -> IconSearchResponse? {
        guard let entry = loaded()[key] else { return nil }
        let age = Date().timeIntervalSince(entry.storedAt)
        guard age < (allowStale ? maxAge : freshAge) else { return nil }
        return entry.response
    }

    func store(_ response: IconSearchResponse, for key: String) {
        var current = loaded()
        current[key] = Entry(storedAt: Date(), response: response)
        current = prune(current)
        entries = current
        if let data = try? JSONEncoder().encode(current) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func loaded() -> [String: Entry] {
        if let entries { return entries }
        let data = try? Data(contentsOf: fileURL)
        let decoded = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = decoded
        return decoded
    }

    /// Drops expired entries first, then the oldest ones if still over the cap.
    private func prune(_ input: [String: Entry]) -> [String: Entry] {
        let now = Date()
        var result = input.filter { now.timeIntervalSince($0.value.storedAt) < maxAge }
        guard result.count > maxEntries else { return result }
        let oldestFirst = result.sorted { $0.value.storedAt < $1.value.storedAt }
        for (key, _) in oldestFirst.prefix(result.count - maxEntries) {
            result[key] = nil
        }
        return result
    }
}
