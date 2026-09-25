import Foundation

enum IconSearchError: LocalizedError {
    case invalidResponse
    case quotaExceeded
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер macosicons.com вернул неожиданный ответ."
        case .quotaExceeded:
            return "Лимит вызовов API macosicons.com для этого ключа исчерпан. Повторные попытки не помогут: нужно дождаться сброса лимита тарифа или использовать другой ключ. Ранее загруженные результаты по-прежнему доступны из кэша."
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
    ///
    /// 429 means two different things here. A plain throttle is worth
    /// retrying with backoff, but when the body says the call limit is
    /// exceeded the key's tariff quota is spent: the server sends no
    /// Retry-After and every retry returns the same 429, so that case fails
    /// fast instead of stalling the UI for the whole backoff budget.
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

        let maxRetries = 3
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IconSearchError.invalidResponse
            }
            if http.statusCode == 429 {
                if Self.isQuotaExceeded(body: data) {
                    throw IconSearchError.quotaExceeded
                }
                guard attempt < maxRetries else {
                    throw IconSearchError.http(429)
                }
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let backoff = min(pow(2.0, Double(attempt)), 20)
                let delay = (retryAfter ?? backoff) + Double.random(in: 0...0.5)
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw IconSearchError.http(http.statusCode)
            }
            return try JSONDecoder().decode(IconSearchResponse.self, from: data)
        }
    }

    /// The quota response is `{"error": true, "statusCode": 429,
    /// "statusMessage": "API call limit exceeded", ...}`; a throttle has no
    /// such message, so an undecodable body is treated as retryable.
    private struct APIErrorBody: Decodable {
        let statusMessage: String?
        let message: String?
    }

    private static func isQuotaExceeded(body: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: body) else {
            return false
        }
        return [decoded.statusMessage, decoded.message]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("limit exceeded") }
    }
}
