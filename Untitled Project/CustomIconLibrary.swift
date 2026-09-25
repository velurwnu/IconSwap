import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct CustomIcon: Identifiable, Hashable {
    let url: URL
    let addedAt: Date

    var id: String { url.lastPathComponent }
}

/// The user's own icon images. Any format NSImage can read works — PNG,
/// JPEG, HEIC, TIFF, ICNS… — so there's no need to convert to .icns first:
/// macOS builds the icon from the image when it's applied.
@Observable
final class CustomIconLibrary {
    private(set) var icons: [CustomIcon] = []
    var selected: CustomIcon?
    var errorMessage: String?

    init() {
        reload()
    }

    func reload() {
        let keys: [URLResourceKey] = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Paths.customIcons, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        icons = urls
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return CustomIcon(url: url, addedAt: date)
            }
            .sorted { $0.addedAt > $1.addedAt }
        if let selected, !icons.contains(selected) {
            self.selected = nil
        }
    }

    func importFiles(_ urls: [URL]) {
        var rejected: [String] = []
        var lastImported: URL?
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard NSImage(contentsOf: url) != nil else {
                rejected.append(url.lastPathComponent)
                continue
            }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let destination = Paths.customIcons.appendingPathComponent("\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                lastImported = destination
            } catch {
                rejected.append(url.lastPathComponent)
            }
        }
        reload()
        if let lastImported {
            selected = icons.first { $0.url == lastImported }
        }
        errorMessage = rejected.isEmpty
            ? nil
            : "Не удалось добавить как изображение: \(rejected.joined(separator: ", "))"
    }

    func delete(_ icon: CustomIcon) {
        try? FileManager.default.removeItem(at: icon.url)
        reload()
    }

    /// Grid thumbnails are decoded downscaled by ImageIO — a 12 MP photo
    /// doesn't get fully decoded just to draw an 88pt cell.
    nonisolated static func thumbnail(for url: URL, maxPixelSize: Int = 256) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

struct CustomIconGridPane: View {
    @Bindable var library: CustomIconLibrary
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = library.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .help(errorMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    addCell
                    ForEach(library.icons) { icon in
                        CustomIconCell(icon: icon, isSelected: library.selected == icon)
                            .onTapGesture { library.selected = icon }
                            .contextMenu {
                                Button("Показать в Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([icon.url])
                                }
                                Button("Удалить", role: .destructive) { library.delete(icon) }
                            }
                    }
                }
                .padding()
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(6)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.importFiles(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                library.importFiles(urls)
            }
        }
    }

    private var addCell: some View {
        Button {
            isImporterPresented = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .medium))
                    .frame(width: 88, height: 88)
                Text("Добавить")
                    .font(.caption)
                Text("PNG, JPEG, HEIC, ICNS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Добавить картинки или перетащить их сюда")
    }
}

private struct CustomIconCell: View {
    let icon: CustomIcon
    let isSelected: Bool
    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 88, height: 88)
            .task(id: icon.id) {
                let url = icon.url
                image = await Task.detached { CustomIconLibrary.thumbnail(for: url) }.value
            }
            Text(icon.url.pathExtension.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
}
