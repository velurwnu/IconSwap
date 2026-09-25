import SwiftUI

/// What gets a new icon: installed apps or user-picked folders.
enum TargetMode: String, CaseIterable, Identifiable {
    case apps = "Приложения"
    case folders = "Папки"
    var id: Self { self }
}

/// Where the icon comes from: macOSicons.com search or the user's own images.
enum IconSource: String, CaseIterable, Identifiable {
    case macOSicons = "macOSicons"
    case custom = "Свои"
    var id: Self { self }
}

struct ContentView: View {
    @State private var appListModel = AppListModel()
    @State private var folderModel = FolderListModel()
    @State private var searchModel = IconSearchModel()
    @State private var customLibrary = CustomIconLibrary()
    @State private var targetMode: TargetMode = .apps
    @State private var iconSource: IconSource = .macOSicons
    @State private var searchText = ""
    @State private var appTemplate: IconTemplate = .appIcon
    @State private var folderTemplate: IconTemplate = .folderEmblem
    @State private var templatePreview: NSImage?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var isRestorerEnabled = false
    @State private var apiKeySheetMode: APIKeySheet.Mode?
    /// Set when Apply hit a root-owned bundle; drives the "fix with admin
    /// password" prompt, after which the same icon is applied again.
    @State private var ownershipFixApp: InstalledApp?

    var body: some View {
        NavigationSplitView {
            Group {
                switch targetMode {
                case .apps:
                    AppListPane(model: appListModel)
                case .folders:
                    FolderListPane(model: folderModel)
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Цель", selection: $targetMode) {
                    ForEach(TargetMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .frame(minWidth: 220, idealWidth: 260)
        } detail: {
            VStack(spacing: 0) {
                sourceBar
                Divider()
                switch iconSource {
                case .macOSicons:
                    IconGridPane(searchModel: searchModel)
                case .custom:
                    CustomIconGridPane(library: customLibrary)
                }
                Divider()
                toolbar
                Divider()
                settingsBar
                Divider()
                footer
            }
            .navigationTitle(targetTitle)
        }
        .task {
            await appListModel.reload()
            searchText = appListModel.selectedApp?.name ?? ""
            searchModel.setQuery(searchText)
            isRestorerEnabled = Restorer.isInstalled()
            if !Keychain.hasAPIKey() {
                apiKeySheetMode = .onboarding
            }
        }
        .onChange(of: appListModel.selectedApp) { _, newApp in
            searchText = newApp?.name ?? ""
            searchIfShowingMacOSicons()
        }
        // Searches only run while the macOSicons grid is visible, so browsing
        // apps with "Свои" selected doesn't spend API quota.
        .onChange(of: iconSource) { _, _ in
            searchIfShowingMacOSicons()
        }
        .onChange(of: targetMode) { _, newMode in
            if newMode == .apps {
                searchText = appListModel.selectedApp?.name ?? searchText
                searchIfShowingMacOSicons()
            }
        }
        .task(id: previewKey) {
            templatePreview = await makeTemplatePreview()
        }
        .sheet(isPresented: Binding(
            get: { apiKeySheetMode != nil },
            set: { if !$0 { apiKeySheetMode = nil } }
        )) {
            APIKeySheet(mode: apiKeySheetMode ?? .edit) { key in
                do {
                    try Keychain.saveAPIKey(key)
                    searchModel.apiKeyDidChange()
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            .interactiveDismissDisabled(apiKeySheetMode == .onboarding)
        }
        .alert("Ошибка", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
        .alert("Нужны права администратора", isPresented: Binding(
            get: { ownershipFixApp != nil },
            set: { if !$0 { ownershipFixApp = nil } }
        )) {
            Button("Разрешить") {
                if let app = ownershipFixApp {
                    fixOwnershipAndApply(app)
                }
            }
            Button("Отмена", role: .cancel) { ownershipFixApp = nil }
        } message: {
            Text("«\(ownershipFixApp?.name ?? "")» принадлежит системе. IconSwap может сделать вас владельцем папки приложения — содержимое приложения не изменится. macOS попросит пароль администратора.")
        }
    }

    private var sourceBar: some View {
        HStack {
            Picker("Источник", selection: $iconSource) {
                ForEach(IconSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if iconSource == .macOSicons {
                TextField("Поиск иконок на macOSicons", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchModel.setQuery(searchText) }
            } else {
                Text("Нажмите «Добавить» или перетащите картинки в сетку")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(8)
    }

    private var toolbar: some View {
        HStack {
            Button("Apply", action: applySelection)
                .disabled(!canApply)
            Button("Revert", action: revertSelected)
                .disabled(!hasTarget)
            if targetMode == .apps {
                Button("Revert All", action: revertAll)
                    .disabled(appListModel.appliedBundleIDs.isEmpty)
            }
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
            if usesTemplate {
                Picker("Шаблон", selection: templateBinding) {
                    ForEach(IconTemplate.options(forFolders: targetMode == .folders)) {
                        Text($0.title).tag($0)
                    }
                }
                .fixedSize()
                Group {
                    if let templatePreview {
                        Image(nsImage: templatePreview)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 40, height: 40)
                .help("Так будет выглядеть иконка")
            }
        }
        .padding(8)
    }

    private var settingsBar: some View {
        HStack {
            Toggle("Сохранять иконки после обновлений", isOn: $isRestorerEnabled)
                .lineLimit(1)
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
            Spacer()
            Button("Изменить API-ключ…") {
                apiKeySheetMode = .edit
            }
        }
        .padding(8)
    }

    private var footer: some View {
        HStack {
            Text("Icons from")
            Link("macOSicons.com", destination: URL(string: "https://macosicons.com")!)
            Spacer()
            Text("Бесплатный тариф: коммерческое использование запрещено")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .padding(8)
    }

    // MARK: - State helpers

    private var targetTitle: String {
        switch targetMode {
        case .apps: return appListModel.selectedApp?.name ?? "IconSwap"
        case .folders: return folderModel.selectedFolder?.name ?? "IconSwap"
        }
    }

    /// macOSicons picks go onto apps unchanged (they're finished icons);
    /// everything else passes through a template.
    private var usesTemplate: Bool {
        iconSource == .custom || targetMode == .folders
    }

    private var currentTemplate: IconTemplate {
        targetMode == .apps ? appTemplate : folderTemplate
    }

    private var templateBinding: Binding<IconTemplate> {
        targetMode == .apps ? $appTemplate : $folderTemplate
    }

    private var hasTarget: Bool {
        switch targetMode {
        case .apps: return appListModel.selectedApp != nil
        case .folders: return folderModel.selectedFolder != nil
        }
    }

    private var hasSource: Bool {
        switch iconSource {
        case .macOSicons: return searchModel.selectedHit != nil
        case .custom: return customLibrary.selected != nil
        }
    }

    private var canApply: Bool {
        guard hasSource, !isBusy else { return false }
        switch targetMode {
        case .apps:
            guard let app = appListModel.selectedApp else { return false }
            return !app.isReadOnly
        case .folders:
            return folderModel.selectedFolder != nil
        }
    }

    private var previewKey: String {
        [
            String(usesTemplate), currentTemplate.rawValue, iconSource.rawValue,
            customLibrary.selected?.id ?? "", searchModel.selectedHit?.id ?? ""
        ].joined(separator: "|")
    }

    private func searchIfShowingMacOSicons() {
        guard iconSource == .macOSicons, searchModel.query != searchText else { return }
        searchModel.setQuery(searchText)
    }

    /// Small render for the toolbar; the macOSicons thumbnail stands in for
    /// the full .icns so previewing never triggers a download.
    private func makeTemplatePreview() async -> NSImage? {
        guard usesTemplate else { return nil }
        let source: NSImage?
        switch iconSource {
        case .custom:
            source = customLibrary.selected.flatMap { NSImage(contentsOf: $0.url) }
        case .macOSicons:
            guard let hit = searchModel.selectedHit else { return nil }
            source = try? await PreviewCache.shared.image(for: hit)
        }
        guard let source else { return nil }
        return IconRenderer.render(source, template: currentTemplate, size: 128)
    }

    /// Full-resolution source image for the current selection.
    private func loadSourceImage() async throws -> (image: NSImage, url: URL?) {
        switch iconSource {
        case .custom:
            guard let icon = customLibrary.selected, let image = NSImage(contentsOf: icon.url) else {
                throw IconSwapError.invalidImage(url: customLibrary.selected?.url ?? Paths.customIcons)
            }
            return (image, icon.url)
        case .macOSicons:
            guard let hit = searchModel.selectedHit else {
                throw IconSwapError.invalidImage(url: Paths.icons)
            }
            let data = try await IconApplier.iconData(for: hit)
            guard let image = NSImage(data: data) else {
                throw IconSwapError.invalidImage(url: Paths.cachedIconURL(objectID: hit.objectID))
            }
            return (image, nil)
        }
    }

    // MARK: - Actions

    private func applySelection() {
        switch targetMode {
        case .apps:
            if let app = appListModel.selectedApp { applyToApp(app) }
        case .folders:
            if let folder = folderModel.selectedFolder { applyToFolder(folder) }
        }
    }

    private func applyToApp(_ app: InstalledApp) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                switch iconSource {
                case .macOSicons:
                    guard let hit = searchModel.selectedHit else { return }
                    try await IconApplier.apply(hit: hit, to: app)
                case .custom:
                    let source = try await loadSourceImage()
                    guard let rendered = IconRenderer.render(source.image, template: appTemplate),
                          let png = IconRenderer.pngData(from: rendered) else {
                        throw IconSwapError.invalidImage(url: source.url ?? Paths.customIcons)
                    }
                    try await IconApplier.apply(customPNG: png, sourceURL: source.url ?? Paths.customIcons, to: app)
                }
                await appListModel.refreshAppliedSet()
                await syncRestorerWatchPathsIfEnabled()
            } catch IconSwapError.ownedByAnotherUser {
                ownershipFixApp = app
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func applyToFolder(_ folder: FolderTarget) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let source = try await loadSourceImage()
                guard let rendered = IconRenderer.render(source.image, template: folderTemplate) else {
                    throw IconSwapError.invalidImage(url: source.url ?? folder.url)
                }
                try FolderIconApplier.apply(rendered, to: folder.url)
                folderModel.iconDidChange()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func fixOwnershipAndApply(_ app: InstalledApp) {
        ownershipFixApp = nil
        isBusy = true
        Task {
            do {
                try await IconApplier.takeOwnership(ofAppAt: app.path)
            } catch {
                isBusy = false
                // Cancelling the password prompt lands here too; nothing to report.
                return
            }
            isBusy = false
            applyToApp(app)
        }
    }

    private func revertSelected() {
        switch targetMode {
        case .apps:
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
        case .folders:
            guard let folder = folderModel.selectedFolder else { return }
            do {
                try FolderIconApplier.reset(folder.url)
                folderModel.iconDidChange()
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
