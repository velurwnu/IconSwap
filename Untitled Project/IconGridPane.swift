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

    private var client: IconSearchClient?
    private var debounceTask: Task<Void, Never>?

    func setQuery(_ text: String) {
        query = text
        selectedHit = nil
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if client == nil {
                client = try IconSearchClient.makeDefault()
            }
            let response = try await client!.search(query: trimmed, page: page)
            hits = reset ? response.hits : hits + response.hits
            self.page = response.page
            totalPages = response.totalPages
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct IconGridPane: View {
    @Bindable var searchModel: IconSearchModel
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = searchModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
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
