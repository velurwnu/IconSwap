import Foundation

struct AppScanner {
    static let searchDirectories: [String] = [
        "/Applications",
        "/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    static func scan() -> [InstalledApp] {
        var seenPaths = Set<String>()
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        for directory in searchDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = directory + "/" + entry
                guard seenPaths.insert(path).inserted else { continue }
                if let app = makeApp(atPath: path) {
                    apps.append(app)
                }
            }
        }
        // Apps the user added by hand from elsewhere on disk. Part of the
        // scan (not just the UI list) so the Restorer finds them too.
        for path in addedAppPaths where seenPaths.insert(path).inserted {
            if let app = makeApp(atPath: path) {
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let addedAppsKey = "addedAppPaths"

    static var addedAppPaths: [String] {
        UserDefaults.standard.stringArray(forKey: addedAppsKey) ?? []
    }

    static func addAppPaths(_ paths: [String]) {
        var current = addedAppPaths
        for path in paths where !current.contains(path) {
            current.append(path)
        }
        UserDefaults.standard.set(current, forKey: addedAppsKey)
    }

    static func removeAddedAppPath(_ path: String) {
        UserDefaults.standard.set(addedAppPaths.filter { $0 != path }, forKey: addedAppsKey)
    }

    private static func makeApp(atPath path: String) -> InstalledApp? {
        guard let bundle = Bundle(path: path) else { return nil }
        let info = bundle.infoDictionary
        let fallbackName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let name = (info?["CFBundleName"] as? String) ?? fallbackName
        let bundleID = bundle.bundleIdentifier
        let version = info?["CFBundleShortVersionString"] as? String
        return InstalledApp(
            id: bundleID ?? path,
            path: path,
            name: name,
            bundleIdentifier: bundleID,
            version: version,
            isReadOnly: IconApplier.isReadOnly(appPath: path)
        )
    }
}
