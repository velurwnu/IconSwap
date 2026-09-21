import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    /// Bundle identifier when available, otherwise the filesystem path —
    /// some utility bundles ship without CFBundleIdentifier.
    let id: String
    let path: String
    let name: String
    let bundleIdentifier: String?
    let version: String?
    /// True only for bundles under /System (SIP-protected); NOT a proxy for
    /// "TCC hasn't granted App Management yet" — see IconApplier.isReadOnly.
    let isReadOnly: Bool

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
