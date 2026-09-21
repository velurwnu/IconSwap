import SwiftUI

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

    func refreshAppliedSet() async {
        let records = await IconStore.shared.allRecords()
        appliedBundleIDs = Set(records.keys)
    }
}

struct AppListPane: View {
    @Bindable var model: AppListModel

    var body: some View {
        List(selection: $model.selectedApp) {
            ForEach(model.filteredApps) { app in
                AppRow(app: app, isApplied: model.appliedBundleIDs.contains(app.bundleIdentifier ?? ""))
                    .tag(app)
                    .opacity(app.isReadOnly ? 0.4 : 1)
                    .allowsHitTesting(!app.isReadOnly)
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Поиск приложений")
        .safeAreaInset(edge: .bottom) {
            Toggle("Только изменённые", isOn: $model.showOnlyChanged)
                .padding(8)
                .background(.bar)
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
