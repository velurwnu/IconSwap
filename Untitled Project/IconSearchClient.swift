import Foundation

enum IconSearchError: LocalizedError {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер macosicons.com вернул неожиданный ответ."
        case .http(let code):
            return "Сервер macosicons.com вернул ошибку HTTP \(code)."
        }
    }
}

/// No mutable state, so a plain struct — not an actor — is enough here.
struct IconSearchClient {
    private let apiKey: String
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.macosicons.com/api/search")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    nonisolated static func makeDefault() throws -> IconSearchClient {
        IconSearchClient(apiKey: try Keychain.readAPIKey())
    }

    /// hitsPerPage is deliberately not sent: verified empirically against the
    /// live API that it's ignored — the server always returns 50 hits/page
    /// regardless of what's requested. Pagination must follow totalPages.
    nonisolated func search(query: String, page: Int) async throws -> IconSearchResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let body: [String: Any] = [
            "query": query,
            "searchOptions": [
                "page": page,
                "sort": ["downloads:desc"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IconSearchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IconSearchError.http(http.statusCode)
        }
        return try JSONDecoder().decode(IconSearchResponse.self, from: data)
    }
}
