import Foundation

enum Paths {
    static let applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("IconSwap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let backups: URL = {
        let dir = applicationSupport.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let icons: URL = {
        let dir = applicationSupport.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let previewCache: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("IconSwap", isDirectory: true).appendingPathComponent("previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let storeFile: URL = applicationSupport.appendingPathComponent("store.json")

    static let launchAgentLabel = "com.velurwnu.IconSwap.restorer"

    static let launchAgentPlist: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }()

    static func backupURL(for bundleID: String) -> URL {
        backups.appendingPathComponent("\(bundleID).icns")
    }

    static func cachedIconURL(objectID: String) -> URL {
        icons.appendingPathComponent("\(objectID).icns")
    }
}
