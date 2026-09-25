import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderTarget: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var name: String { FileManager.default.displayName(atPath: url.path) }
}

/// Folders the user picked for custom icons, persisted by path (the app
/// isn't sandboxed, so no security-scoped bookmarks are needed).
@Observable
final class FolderListModel {
    private static let defaultsKey = "folderTargets"

    private(set) var folders: [FolderTarget] = []
    var selectedFolder: FolderTarget?
    /// Bumped after an icon change so rows re-read the folder's icon.
    private(set) var iconRevision = 0

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        folders = paths
            .filter { Self.isFolder(URL(fileURLWithPath: $0)) }
            .map { FolderTarget(url: URL(fileURLWithPath: $0)) }
        selectedFolder = folders.first
    }

    func add(_ urls: [URL]) {
        var added: FolderTarget?
        for url in urls where Self.isFolder(url) {
            let target = FolderTarget(url: url.standardizedFileURL)
            guard !folders.contains(target) else {
                added = target
                continue
            }
            folders.append(target)
            added = target
        }
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        if let added {
            selectedFolder = added
        }
    }

    /// Only removes the folder from the list; its icon stays as it is.
    func remove(_ folder: FolderTarget) {
        folders.removeAll { $0 == folder }
        if selectedFolder == folder {
            selectedFolder = folders.first
        }
        persist()
    }

    func iconDidChange() {
        iconRevision += 1
    }

    private func persist() {
        UserDefaults.standard.set(folders.map(\.url.path), forKey: Self.defaultsKey)
    }

    /// App bundles are directories too, but they belong in the Apps list.
    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}

struct FolderListPane: View {
    @Bindable var model: FolderListModel
    @State private var isImporterPresented = false

    var body: some View {
        List(selection: $model.selectedFolder) {
            ForEach(model.folders) { folder in
                FolderRow(folder: folder, revision: model.iconRevision)
                    .tag(folder)
                    .contextMenu {
                        Button("Показать в Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        }
                        Button("Убрать из списка") { model.remove(folder) }
                    }
            }
        }
        .overlay {
            if model.folders.isEmpty {
                ContentUnavailableView(
                    "Нет папок",
                    systemImage: "folder",
                    description: Text("Добавьте папку кнопкой ниже или перетащите её сюда из Finder.")
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Добавить папку…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .sidebarCapsuleStyle(prominent: false)
            .padding(8)
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.add(urls)
            }
        }
    }
}

private struct FolderRow: View {
    let folder: FolderTarget
    let revision: Int

    var body: some View {
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.url.path))
                .resizable()
                .frame(width: 28, height: 28)
                .id(revision)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .lineLimit(1)
                Text((folder.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .help(folder.url.path)
    }
}

enum FolderIconApplier {
    static func apply(_ image: NSImage, to folder: URL) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw IconSwapError.appNotFound(path: folder.path)
        }
        guard NSWorkspace.shared.setIcon(image, forFile: folder.path, options: []) else {
            throw IconSwapError.setIconFailed(path: folder.path)
        }
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
    }

    static func reset(_ folder: URL) throws {
        guard NSWorkspace.shared.setIcon(nil, forFile: folder.path, options: []) else {
            throw IconSwapError.setIconFailed(path: folder.path)
        }
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
    }
}
