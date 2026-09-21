import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Applies and reverts custom application icons via NSWorkspace only.
/// Never touches anything inside an app bundle's Contents/ directory —
/// setIcon itself writes a sibling "Icon\r" file / custom-icon flag at the
/// bundle root, which is the same place the writability probe below checks.
struct IconApplier {

    /// True only for genuinely SIP-protected bundles. Deliberately does NOT
    /// fall back to `FileManager.isWritableFile`: verified empirically that
    /// once TCC denies the "App Management" grant, `isWritableFile` (and
    /// `access()` under it) also reports `false` for perfectly ordinary
    /// /Applications bundles — using it here would mislabel a fixable
    /// permission prompt as an unfixable SIP restriction.
    static func isReadOnly(appPath: String) -> Bool {
        appPath.hasPrefix("/System/")
    }

    static func apply(imageURL: URL, toAppAt appPath: String, bundleID: String) throws {
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw IconSwapError.appNotFound(path: appPath)
        }
        guard !isReadOnly(appPath: appPath) else {
            throw IconSwapError.readOnlyApp(path: appPath)
        }
        guard let image = NSImage(contentsOf: imageURL) else {
            throw IconSwapError.invalidImage(url: imageURL)
        }

        try backupOriginalIconIfNeeded(bundleID: bundleID, appPath: appPath)
        try probeWritable(appPath: appPath)

        guard NSWorkspace.shared.setIcon(image, forFile: appPath, options: []) else {
            throw IconSwapError.setIconFailed(path: appPath)
        }
        refresh(appPath: appPath)
    }

    static func reset(appAt appPath: String) throws {
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw IconSwapError.appNotFound(path: appPath)
        }
        try probeWritable(appPath: appPath)
        guard NSWorkspace.shared.setIcon(nil, forFile: appPath, options: []) else {
            throw IconSwapError.setIconFailed(path: appPath)
        }
        refresh(appPath: appPath)
    }

    static func backupOriginalIconIfNeeded(bundleID: String, appPath: String) throws {
        let backupURL = Paths.backupURL(for: bundleID)
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        try writeICNS(icon, to: backupURL)
    }

    /// Sizes (in points) rendered into the backup .icns. Verified empirically:
    /// some individual sizes (1024px/64px alone) make CGImageDestination's
    /// icns encoder fail outright — it needs a couple of sizes together to
    /// disambiguate the @1x/@2x icon slot. 512+256+128+32 reliably succeeds.
    private static let icnsBackupSizes = [512, 256, 128, 32]

    static func writeICNS(_ image: NSImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, icnsBackupSizes.count, nil) else {
            throw IconSwapError.invalidImage(url: url)
        }
        var addedAny = false
        for size in icnsBackupSizes {
            var rect = NSRect(x: 0, y: 0, width: size, height: size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high]),
                  let normalized = normalizedTo8Bit(cgImage) else { continue }
            CGImageDestinationAddImage(destination, normalized, nil)
            addedAny = true
        }
        guard addedAny, CGImageDestinationFinalize(destination) else {
            throw IconSwapError.invalidImage(url: url)
        }
    }

    /// NSWorkspace icons can come back as 16-bit extended-range (HDR) images;
    /// the icns encoder is happiest with plain 8-bit sRGB, so normalize first.
    private static func normalizedTo8Bit(_ source: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: source.width, height: source.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()
    }

    /// setIcon() only returns a Bool, so to surface a real reason (a missing
    /// "App Management" TCC grant vs. a genuine I/O error) we probe write
    /// access at the same location setIcon needs to write to, before calling it.
    private static func probeWritable(appPath: String) throws {
        let probeURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent(".iconswap-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL)
            try FileManager.default.removeItem(at: probeURL)
        } catch let error as NSError {
            if (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError)
                || (error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM)) {
                throw IconSwapError.permissionDenied(path: appPath)
            }
            throw IconSwapError.permissionDenied(path: appPath)
        }
    }

    static func refresh(appPath: String) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: appPath)
        NSWorkspace.shared.noteFileSystemChanged(appPath)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}

extension IconApplier {
    /// Downloads the hit's .icns to a temp file (named by extension, never by
    /// the server's Content-Type header — verified empirically that icns
    /// assets are served as "text/plain"), applies it, caches a local copy
    /// for the Restorer, and records the choice in IconStore.
    nonisolated static func apply(hit: IconHit, to app: InstalledApp) async throws {
        guard let bundleID = app.bundleIdentifier else {
            throw IconSwapError.appNotFound(path: app.path)
        }
        guard let remoteURL = hit.iconURL else {
            throw IconSwapError.invalidImage(url: URL(fileURLWithPath: app.path))
        }

        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IconSwapError.downloadFailed(underlying: URLError(.badServerResponse))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("icns")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try apply(imageURL: tempURL, toAppAt: app.path, bundleID: bundleID)

        let cachedURL = Paths.cachedIconURL(objectID: hit.objectID)
        try? FileManager.default.removeItem(at: cachedURL)
        try data.write(to: cachedURL)

        let record = IconStoreRecord(
            iconURL: hit.icnsUrl,
            previewURL: hit.lowResPngUrl,
            appliedAt: Date(),
            appVersion: app.version,
            author: hit.usersName,
            sourceURL: hit.authorURL?.absoluteString ?? hit.uploadedBy,
            cachedIconPath: cachedURL.path
        )
        try await IconStore.shared.setRecord(record, for: bundleID)
    }

    nonisolated static func revertToOriginal(_ app: InstalledApp) async throws {
        try reset(appAt: app.path)
        if let bundleID = app.bundleIdentifier {
            try await IconStore.shared.removeRecord(for: bundleID)
        }
    }
}
