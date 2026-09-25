import AppKit
import SwiftUI

@Observable
final class IconSearchModel {
    private(set) var query: String = ""
    private(set) var hits: [IconHit] = []
    private(set) var page = 1
    private(set) var totalPages = 1
    private(set) var isLoading = false
    var errorMessage: String?
    var selectedHit: IconHit?
    /// Set once the key's call quota is spent. Further requests would return
    /// the same 429, so searching stops until the user retries explicitly —
    /// otherwise every click on an app burns another doomed call. Persisted
    /// until the quota resets so a relaunch doesn't spend a call to find out.
    private(set) var isQuotaExhausted = QuotaBlock.isActive

    private var client: IconSearchClient?
    private var debounceTask: Task<Void, Never>?
    /// Switching between apps re-issues the same query repeatedly (every
    /// click re-searches for that app's name), so identical query+page
    /// requests are served from here instead of hitting the rate limit again.
    private var responseCache: [String: IconSearchResponse] = [:]
    /// Network requests are shared per query+page and never cancelled when
    /// the user moves on: the call is already paid for once it's sent, so
    /// its result is cached rather than thrown away and re-bought later.
    private var inFlight: [String: Task<IconSearchResponse, Error>] = [:]

    func setQuery(_ text: String) {
        query = text
        selectedHit = nil
        debounceTask?.cancel()
        debounceTask = Task {
            // Long enough that arrowing through the app list doesn't fire a
            // paid search for every app passed on the way.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await performSearch(page: 1, reset: true)
        }
    }

    func loadMoreIfNeeded(currentItem hit: IconHit) async {
        guard let index = hits.firstIndex(of: hit) else { return }
        guard index >= hits.count - 10, page < totalPages, !isLoading else { return }
        await performSearch(page: page + 1, reset: false)
    }

    private func performSearch(page: Int, reset: Bool) async {
        let requestedQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        let cacheKey = SearchResponseCache.key(query: trimmed, page: page)
        var cachedResponse = responseCache[cacheKey]
        if cachedResponse == nil {
            cachedResponse = await SearchResponseCache.shared.response(for: cacheKey)
        }
        if let cached = cachedResponse {
            responseCache[cacheKey] = cached
            apply(cached, reset: reset)
            return
        }
        guard !isQuotaExhausted else {
            if !(await applyStale(cacheKey, reset: reset)) {
                if reset { hits = [] }
            }
            errorMessage = IconSearchError.quotaExceeded.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await fetch(query: trimmed, page: page, cacheKey: cacheKey)
            // The user may have picked another app while this was loading;
            // the result is cached either way, just not shown.
            guard query == requestedQuery else { return }
            apply(response, reset: reset)
        } catch {
            if case IconSearchError.quotaExceeded = error {
                isQuotaExhausted = true
                QuotaBlock.activate()
            }
            guard query == requestedQuery else { return }
            let usedStale = await applyStale(cacheKey, reset: reset)
            if !usedStale || isQuotaExhausted {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetch(query: String, page: Int, cacheKey: String) async throws -> IconSearchResponse {
        if let running = inFlight[cacheKey] {
            return try await running.value
        }
        if client == nil {
            client = try IconSearchClient.makeDefault()
        }
        guard let client else { throw IconSearchError.invalidResponse }
        // Unstructured on purpose, so cancelling the caller doesn't cancel
        // a request that has already been counted against the quota.
        let task = Task {
            let response = try await client.search(query: query, page: page)
            await SearchResponseCache.shared.store(response, for: cacheKey)
            return response
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }
        let response = try await task.value
        responseCache[cacheKey] = response
        return response
    }

    /// Falls back to an expired cache entry when a fresh one can't be had.
    private func applyStale(_ cacheKey: String, reset: Bool) async -> Bool {
        guard let stale = await SearchResponseCache.shared.response(for: cacheKey, allowStale: true) else {
            return false
        }
        apply(stale, reset: reset)
        return true
    }

    private func apply(_ response: IconSearchResponse, reset: Bool) {
        hits = reset ? response.hits : hits + response.hits
        page = response.page
        totalPages = response.totalPages
    }

    /// The quota window may have reset since the last failure, so let the
    /// user unblock searching without relaunching the app.
    func retryAfterQuotaError() {
        isQuotaExhausted = false
        QuotaBlock.clear()
        errorMessage = nil
        debounceTask?.cancel()
        debounceTask = Task { await performSearch(page: 1, reset: true) }
    }

    /// The cached client closes over the old key, so it must be dropped or
    /// every request after a key change would keep authenticating with the
    /// value the user just replaced.
    func apiKeyDidChange() {
        client = nil
        isQuotaExhausted = false
        QuotaBlock.clear()
        errorMessage = nil
        debounceTask?.cancel()
        debounceTask = Task { await performSearch(page: 1, reset: true) }
    }
}

/// Remembers a spent quota across launches. macosicons.com resets usage on
/// the 1st of each month (UTC), so the block lifts itself at that moment.
private enum QuotaBlock {
    private static let defaultsKey = "searchQuotaBlockedUntil"

    static var isActive: Bool {
        guard let until = UserDefaults.standard.object(forKey: defaultsKey) as? Date else { return false }
        return Date() < until
    }

    static func activate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }
        UserDefaults.standard.set(nextMonth, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

struct IconGridPane: View {
    @Bindable var searchModel: IconSearchModel
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = searchModel.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Capped at a few lines: an unbounded message raises the
                    // content's minimum height and macOS grows the window to
                    // fit it, past the bottom of a laptop screen. The full
                    // text stays available as a tooltip.
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .help(errorMessage)
                    Spacer()
                    if searchModel.isQuotaExhausted {
                        Button("Повторить", action: searchModel.retryAfterQuotaError)
                    }
                }
                .padding(8)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(searchModel.hits) { hit in
                        IconGridCell(
                            hit: hit,
                            isSelected: searchModel.selectedHit?.id == hit.id,
                            onSelect: { searchModel.selectedHit = hit }
                        )
                        .task { await searchModel.loadMoreIfNeeded(currentItem: hit) }
                    }
                }
                .padding()
            }
            if searchModel.isLoading {
                ProgressView().padding(8)
            }
        }
    }
}

private struct IconGridCell: View {
    let hit: IconHit
    let isSelected: Bool
    var onSelect: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 88, height: 88)
            .task {
                image = try? await PreviewCache.shared.image(for: hit)
            }
            Text(hit.appName)
                .font(.caption)
                .lineLimit(1)
            Link(hit.usersName, destination: hit.authorURL ?? URL(string: "https://macosicons.com")!)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
