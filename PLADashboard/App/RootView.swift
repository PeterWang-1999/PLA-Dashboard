import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(DashboardSettingsNotifier.self) private var dashboardSettingsNotifier
    @SceneStorage("dashboard.sidebarVisible") private var sidebarVisibleStorage = true

    @State private var windowState = WindowState()
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var importViewModel = ImportViewModel()
    @State private var selectedNavigationItem: AppNavigationItem? = .dashboard
    @State private var showImportBlockingAlert = false

    private static var importAllowedContentTypes: [UTType] {
        var types: [UTType] = [
            .commaSeparatedText,
            .tabSeparatedText,
            .plainText,
            .text,
            .data,
            .spreadsheet
        ]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        return types
    }

    var body: some View {
        let workspaceRevision = accountStore.workspaceRevision
        let settingsRevision = dashboardSettingsNotifier.revision

        NavigationSplitView(columnVisibility: $windowState.columnVisibility) {
            sidebar
        } detail: {
            detailContent
                .focusedSceneValue(\.windowState, windowState)
                .focusedSceneValue(\.triggerImportPicker) {
                    selectedNavigationItem = .imports
                    importViewModel.presentImportPicker()
                }
                .focusedSceneValue(\.refreshDashboardAggregation) {
                    Task { @MainActor in
                        await dashboardViewModel.rebuildMetricsAndRefresh()
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .fileImporter(
            isPresented: $importViewModel.showFileImporter,
            allowedContentTypes: RootView.importAllowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                importViewModel.handleImportedURLs(urls)
            case .failure(let error):
                importViewModel.errorMessage = ImportUserFacingError.message(for: error)
            }
        }
        .onAppear {
            windowState.syncFromSceneStorage(sidebarVisibleStorage)
        }
        .onChange(of: windowState.columnVisibility) { _, visibility in
            windowState.isSidebarVisible = visibility != .detailOnly
            sidebarVisibleStorage = windowState.isSidebarVisible
        }
        .task(id: workspaceRevision) {
            await reloadWorkspaceContent()
        }
        .onChange(of: settingsRevision) { _, _ in
            dashboardViewModel.handleSettingsDidChange()
        }
        .alert("无法切换账户", isPresented: $showImportBlockingAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("导入进行中，请先取消导入或等待完成。")
        }
    }

    private var sidebarNavigationItems: [AppNavigationItem] {
        accountStore.activeCapabilities?.sidebarNavigationItems ?? AppNavigationItem.defaultSidebarCases
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedNavigationItem) {
                Section("导航") {
                    ForEach(sidebarNavigationItems) { item in
                        Label(item.rawValue, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            AccountSwitcherView(
                isImportInProgress: importViewModel.isImporting,
                onSwitchBlocked: { showImportBlockingAlert = true }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("PLA Dashboard")
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("切换侧边栏")
                .accessibilityLabel("切换侧边栏")
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedNavigationItem ?? .dashboard {
        case .dashboard:
            NavigationStack {
                DashboardView(
                    viewModel: dashboardViewModel,
                    windowState: windowState,
                    onRequestDataUpdate: {
                        selectedNavigationItem = .imports
                        importViewModel.presentImportPicker()
                    }
                )
            }
        case .imports:
            NavigationStack {
                ImportsView(viewModel: importViewModel)
            }
        }
    }

    private func reloadWorkspaceContent() async {
        guard let activeAccountID = accountStore.activeAccountID,
              let databaseClient = accountStore.activeDatabaseClient,
              databaseClient.accountID == activeAccountID else {
            return
        }

        dashboardViewModel.resetForAccountSwitch()
        importViewModel.resetForAccountSwitch()
        configureViewModels(databaseClient: databaseClient)
        await dashboardViewModel.reloadFilterCatalogsFromDatabase()
        await dashboardViewModel.bootstrapDashboard()
        await importViewModel.loadHistory()
        if let capabilities = accountStore.activeCapabilities,
           let selected = selectedNavigationItem,
           !capabilities.sidebarNavigationItems.contains(selected) {
            selectedNavigationItem = .dashboard
        }
    }

    private func configureViewModels(databaseClient: DatabaseClient) {
        let capabilities = accountStore.activeCapabilities
            ?? WorkspaceCapabilities.forKind(.thirdParty)

        dashboardViewModel.configure(
            databaseClient: databaseClient,
            accountKind: accountStore.activeAccount?.kind ?? .thirdParty
        ) {
            await dashboardViewModel.bootstrapDashboard()
        }
        importViewModel.configure(
            databaseClient: databaseClient,
            capabilities: capabilities,
            accountKind: accountStore.activeAccount?.kind ?? .thirdParty,
            onReloadFilterCatalogs: {
                await dashboardViewModel.reloadFilterCatalogsFromDatabase()
            },
            onImportCompleted: {
                await dashboardViewModel.handleImportCompleted()
            }
        )
    }
}
