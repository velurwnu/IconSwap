import Foundation

/// Modeled on the actual macosicons.com /api/search response (verified with
/// a live request), not on the field names implied by the docs.
struct IconSearchResponse: Codable {
    let hits: [IconHit]
    let query: String
    let page: Int
    let totalPages: Int
    let totalHits: Int
}

struct IconHit: Codable, Identifiable, Hashable {
    let objectID: String
    let appName: String
    let icnsUrl: String
    let lowResPngUrl: String
    let downloads: Int
    let usersName: String
    /// Often null in practice — fall back to the uploader's profile link.
    let credit: String?
    let uploadedBy: String

    var id: String { objectID }

    var authorURL: URL? {
        URL(string: credit ?? uploadedBy)
    }

    var iconURL: URL? { URL(string: icnsUrl) }
    var previewURL: URL? { URL(string: lowResPngUrl) }
}
