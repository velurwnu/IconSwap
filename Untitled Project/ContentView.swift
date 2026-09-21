import SwiftUI

struct ContentView: View {
    @State private var appListModel = AppListModel()
    @State private var searchModel = IconSearchModel()
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var isRestorerEnabled = false

    var body: some View {
        NavigationSplitView {
            AppListPane(model: appListModel)
                .frame(minWidth: 220, idealWidth: 260)
        } detail: {
            VStack(spacing: 0) {
                IconGridPane(searchModel: searchModel)
                Divider()
                toolbar
                Divider()
                settingsBar
                Divider()
                footer
            }
            .navigationTitle(appListModel.selectedApp?.name ?? "IconSwap")
        }
        .task {
            await appListModel.reload()
            searchModel.setQuery(appListModel.selectedApp?.name ?? "")
            isRestorerEnabled = Restorer.isInstalled()
        }
        .onChange(of: appListModel.selectedApp) { _, newApp in
            searchModel.setQuery(newApp?.name ?? "")
        }
        .alert("Ошибка", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Apply", action: applySelectedHit)
                .disabled(!canApply)
            Button("Revert", action: revertSelected)
                .disabled(appListModel.selectedApp == nil)
            Button("Revert All", action: revertAll)
                .disabled(appListModel.appliedBundleIDs.isEmpty)
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(8)
    }

    private var settingsBar: some View {
        Toggle("Сохранять иконки после обновлений", isOn: $isRestorerEnabled)
            .padding(8)
            .onChange(of: isRestorerEnabled) { _, enabled in
                Task {
                    do {
                        if enabled {
                            try await Restorer.install()
                        } else {
                            Restorer.uninstall()
                        }
                    } catch {
                        statusMessage = error.localizedDescription
                        isRestorerEnabled = Restorer.isInstalled()
                    }
                }
            }
    }

    private var footer: some View {
        HStack {
            Text("Icons from")
            Link("macOSicons.com", destination: URL(string: "https://macosicons.com")!)
            Spacer()
            Text("Бесплатный тариф: коммерческое использование запрещено")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
    }

    private var canApply: Bool {
        guard let app = appListModel.selectedApp, !app.isReadOnly else { return false }
        return searchModel.selectedHit != nil
    }

    private func applySelectedHit() {
        guard let app = appListModel.selectedApp, let hit = searchModel.selectedHit else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await IconApplier.apply(hit: hit, to: app)
                await appListModel.refreshAppliedSet()
                await syncRestorerWatchPathsIfEnabled()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func revertSelected() {
        guard let app = appListModel.selectedApp else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await IconApplier.revertToOriginal(app)
                await appListModel.refreshAppliedSet()
                await syncRestorerWatchPathsIfEnabled()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func revertAll() {
        isBusy = true
        Task {
            defer { isBusy = false }
            let appliedIDs = appListModel.appliedBundleIDs
            for app in appListModel.apps where appliedIDs.contains(app.bundleIdentifier ?? "") {
                do {
                    try await IconApplier.revertToOriginal(app)
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            await appListModel.refreshAppliedSet()
            await syncRestorerWatchPathsIfEnabled()
        }
    }

    /// The LaunchAgent's WatchPaths list is fixed at install time; keep it
    /// current whenever the set of tracked apps changes while it's enabled.
    private func syncRestorerWatchPathsIfEnabled() async {
        guard isRestorerEnabled else { return }
        try? await Restorer.install()
    }
}

#Preview {
    ContentView()
}
