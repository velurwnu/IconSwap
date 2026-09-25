import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// How a source image is turned into the final icon. Rendered locally, so
/// none of these spend macOSicons API quota.
enum IconTemplate: String, CaseIterable, Identifiable {
    /// The image as-is, fitted into a square canvas.
    case original
    /// macOS app-icon shape: rounded square on Apple's 824/1024 grid.
    case appIcon
    /// The image placed as a framed photo on the front of a folder.
    case folderEmblem
    /// The image itself cut to the folder silhouette, keeping its shading.
    case folderShape

    var id: Self { self }

    var title: String {
        switch self {
        case .original: return "Как есть"
        case .appIcon: return "Иконка macOS"
        case .folderEmblem: return "Фото на папке"
        case .folderShape: return "Папка из фото"
        }
    }

    /// Folder shapes make no sense on an app icon, so apps get a shorter list.
    static func options(forFolders: Bool) -> [IconTemplate] {
        forFolders ? allCases : [.original, .appIcon]
    }
}

enum IconRenderer {
    static func render(_ image: NSImage, template: IconTemplate, size: CGFloat = 1024) -> NSImage? {
        let renderer = ImageRenderer(content: TemplateView(image: image, template: template, size: size))
        renderer.scale = 1
        return renderer.nsImage
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct TemplateView: View {
    let image: NSImage
    let template: IconTemplate
    let size: CGFloat

    var body: some View {
        content
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        switch template {
        case .original:
            source.scaledToFit()
        case .appIcon:
            let side = size * 824 / 1024
            source
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: size * 0.012, y: size * 0.01)
        case .folderEmblem:
            // The emblem sits on the folder's front panel, which in the
            // system folder artwork spans roughly 24–86% of the height.
            let shape = RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
            ZStack {
                folder.scaledToFit()
                source
                    .scaledToFill()
                    .frame(width: size * 0.5, height: size * 0.36)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: size * 0.008))
                    .shadow(color: .black.opacity(0.25), radius: size * 0.01, y: size * 0.006)
                    .offset(y: size * 0.07)
            }
        case .folderShape:
            // The photo takes the folder's alpha as its mask; the folder art
            // is blended back on top so the tab and edge shading still read.
            source
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .overlay(folder.scaledToFit().blendMode(.overlay).opacity(0.6))
                .mask(folder.scaledToFit())
        }
    }

    private var source: some View {
        Image(nsImage: image).resizable().interpolation(.high)
    }

    /// Handed straight to ImageRenderer, the workspace icon draws from a
    /// small representation and comes out blurry, so the full-size bitmap
    /// is pulled out explicitly first.
    private var folder: Image {
        let icon = NSWorkspace.shared.icon(for: .folder)
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        if let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high]) {
            return Image(decorative: cgImage, scale: 1).resizable().interpolation(.high)
        }
        return Image(nsImage: icon).resizable().interpolation(.high)
    }
}
