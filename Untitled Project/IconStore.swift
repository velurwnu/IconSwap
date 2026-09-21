import Foundation

struct IconStoreRecord: Codable {
    let iconURL: String
    let previewURL: String
    var appliedAt: Date
    let appVersion: String?
    let author: String
    let sourceURL: String
    /// Local copy of the applied .icns, used by Restorer to reapply without network.
    let cachedIconPath: String
}

private struct IconStoreFile: Codable {
    var version: Int = 1
    var records: [String: IconStoreRecord] = [:]
}

/// bundleID -> applied-icon record, persisted so icons can be reapplied
/// after app updates without re-hitting the network.
actor IconStore {
    static let shared = IconStore()
    private var file: IconStoreFile

    private init() {
        if let data = try? Data(contentsOf: Paths.storeFile),
           let decoded = try? JSONDecoder().decode(IconStoreFile.self, from: data) {
            file = decoded
        } else {
            file = IconStoreFile()
        }
    }

    func record(for bundleID: String) -> IconStoreRecord? {
        file.records[bundleID]
    }

    func allRecords() -> [String: IconStoreRecord] {
        file.records
    }

    func setRecord(_ record: IconStoreRecord, for bundleID: String) throws {
        file.records[bundleID] = record
        try persist()
    }

    func removeRecord(for bundleID: String) throws {
        file.records[bundleID] = nil
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(file)
        try data.write(to: Paths.storeFile, options: .atomic)
    }
}
