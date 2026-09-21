import Foundation

/// Installs/uninstalls a LaunchAgent that watches each tracked app's
/// Info.plist and re-invokes this same binary (`iconswap restore`) whenever
/// one changes — i.e. after an app update, which is exactly when macOS tends
/// to reset a custom icon.
struct Restorer {
    static let label = Paths.launchAgentLabel

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgentPlist.path)
    }

    nonisolated static func install() async throws {
        try await writePlist()
        bootout()
        try bootstrap()
    }

    nonisolated static func uninstall() {
        bootout()
        try? FileManager.default.removeItem(at: Paths.launchAgentPlist)
    }

    /// Reapplies every stored icon from its local cache (no network). Called
    /// by the LaunchAgent and by `iconswap restore`. Deliberately
    /// unconditional rather than trying to detect whether the icon actually
    /// reverted first — reapplying an already-correct icon is a harmless no-op.
    nonisolated static func restoreAll() async throws {
        let records = await IconStore.shared.allRecords()
        guard !records.isEmpty else { return }
        let apps = AppScanner.scan()
        for (bundleID, record) in records {
            guard let app = apps.first(where: { $0.bundleIdentifier == bundleID }) else { continue }
            let cachedURL = URL(fileURLWithPath: record.cachedIconPath)
            guard FileManager.default.fileExists(atPath: cachedURL.path) else { continue }
            try IconApplier.apply(imageURL: cachedURL, toAppAt: app.path, bundleID: bundleID)
        }
    }

    private static func watchPaths() async -> [String] {
        let records = await IconStore.shared.allRecords()
        let apps = AppScanner.scan()
        return records.keys.compactMap { bundleID in
            apps.first(where: { $0.bundleIdentifier == bundleID })?.path
        }.map { "\($0)/Contents/Info.plist" }
    }

    private static func writePlist() async throws {
        guard let executablePath = Bundle.main.executablePath else {
            throw IconSwapError.appNotFound(path: "IconSwap")
        }
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "restore"],
            "WatchPaths": await watchPaths(),
            "RunAtLoad": false
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: Paths.launchAgentPlist.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: Paths.launchAgentPlist, options: .atomic)
    }

    private static func bootout() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func bootstrap() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(getuid())", Paths.launchAgentPlist.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw IconSwapError.setIconFailed(path: Paths.launchAgentPlist.path)
        }
    }
}
