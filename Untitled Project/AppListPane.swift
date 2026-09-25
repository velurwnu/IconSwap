import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppListModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var appliedBundleIDs: Set<String> = []
    var searchText: String = ""
    var showOnlyChanged: Bool = false
    var selectedApp: InstalledApp?

    var filteredApps: [InstalledApp] {
        apps.filter { app in
            if showOnlyChanged, !appliedBundleIDs.contains(app.bundleIdentifier ?? "") {
                return false
            }
            if !searchText.isEmpty, !app.name.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    func reload() async {
        apps = AppScanner.scan()
        await refreshAppliedSet()
        if selectedApp == nil {
            selectedApp = apps.first
        }
    }

    /// Adds .app bundles picked from anywhere on disk and selects the last one.
    func addApps(_ urls: [URL]) async {
        let paths = urls
            .filter { $0.pathExtension.lowercased() == "app" }
            .map { $0.standardizedFileURL.path }
        guard !paths.isEmpty else { return }
        AppScanner.addAppPaths(paths)
        await reload()
        if let last = paths.last, let app = apps.first(where: { $0.path == last }) {
            selectedApp = app
        }
    }

    func isAddedByUser(_ app: InstalledApp) -> Bool {
        AppScanner.addedAppPaths.contains(app.path)
    }

    /// Only drops it from the list; an applied icon stays on the app.
    func removeAddedApp(_ app: InstalledApp) async {
        AppScanner.removeAddedAppPath(app.path)
        if selectedApp == app {
            selectedApp = nil
        }
        await reload()
    }

    func refreshAppliedSet() async {
        let records = await IconStore.shared.allRecords()
        appliedBundleIDs = Set(records.keys)
    }
}

struct AppListPane: View {
    @Bindable var model: AppListModel
    @State private var isImporterPresented = false

    var body: some View {
        List(selection: $model.selectedApp) {
            ForEach(model.filteredApps) { app in
                AppRow(app: app, isApplied: model.appliedBundleIDs.contains(app.bundleIdentifier ?? ""))
                    .tag(app)
                    .opacity(app.isReadOnly ? 0.4 : 1)
                    .allowsHitTesting(!app.isReadOnly)
                    .contextMenu {
                        Button("Показать в Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                        }
                        if model.isAddedByUser(app) {
                            Button("Убрать из списка") {
                                Task { await model.removeAddedApp(app) }
                            }
                        }
                    }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Поиск приложений")
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.addApps(urls) }
            return true
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                OnlyChangedButton(isOn: $model.showOnlyChanged)
                AddAppButton { isImporterPresented = true }
            }
            .padding(8)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await model.addApps(urls) }
            }
        }
    }
}

/// Round "+" next to the filter capsule: adds an app from anywhere on disk.
private struct AddAppButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .padding(.vertical, 4)
        }
        .sidebarCapsuleStyle(prominent: false, shape: .circle)
        .help("Добавить приложение с диска")
    }
}

/// Full-width capsule that toggles the "only changed" filter; highlighted
/// (prominent glass) while the filter is on.
private struct OnlyChangedButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label("Только изменённые", systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .sidebarCapsuleStyle(prominent: isOn)
    }
}

extension View {
    /// Large full-width capsule used for the sidebar's bottom buttons.
    /// Liquid Glass needs macOS 26; older systems get a bordered capsule.
    @ViewBuilder
    func sidebarCapsuleStyle(prominent: Bool, shape: ButtonBorderShape = .capsule) -> some View {
        let base = self
            .controlSize(.large)
            .buttonBorderShape(shape)
        if #available(macOS 26, *) {
            if prominent {
                base.buttonStyle(.glassProminent)
            } else {
                base.buttonStyle(.glass)
            }
        } else if prominent {
            base.buttonStyle(.borderedProminent)
        } else {
            base.buttonStyle(.bordered)
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isApplied: Bool

    var body: some View {
        HStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                if let version = app.version {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isApplied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if app.isReadOnly {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help("Защищено системой (SIP)")
            }
        }
    }
}
