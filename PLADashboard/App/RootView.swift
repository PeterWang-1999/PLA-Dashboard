import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AccountStore.self) private var accountStore
    @SceneStorage("dashboard.sidebarVisible") private var sidebarVisibleStorage = true

    @State private var windowState = WindowState()
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var importViewModel = ImportViewModel()
    @State private var selectedNavigationItem: AppNavigationItem? = .dashboard

    var body: some View {
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
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                importViewModel.handleImportedURLs(urls)
            case .failure(let error):
                importViewModel.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            windowState.syncFromSceneStorage(sidebarVisibleStorage)
        }
        .onChange(of: windowState.columnVisibility) { _, visibility in
            windowState.isSidebarVisible = visibility != .detailOnly
            sidebarVisibleStorage = windowState.isSidebarVisible
        }
        .task(id: accountStore.activeAccountID) {
            guard let databaseClient = accountStore.activeDatabaseClient else { return }
            dashboardViewModel.resetForAccountSwitch()
            importViewModel.resetForAccountSwitch()
            configureViewModels(databaseClient: databaseClient)
            await bootstrapDashboardIfNeeded(databaseClient: databaseClient)
            await importViewModel.loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardSettingsDidChange)) { _ in
            dashboardViewModel.handleSettingsDidChange()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedNavigationItem) {
            Section("导航") {
                ForEach(AppNavigationItem.sidebarCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
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
        case .settings:
            EmptyView()
        }
    }

    private func configureViewModels(databaseClient: DatabaseClient) {
        dashboardViewModel.configure(databaseClient: databaseClient) {
            await bootstrapDashboardIfNeeded(databaseClient: databaseClient)
        }
        importViewModel.configure(databaseClient: databaseClient) { url in
            try? dashboardViewModel.reloadFilterCatalogs(from: url)
        } onImportCompleted: {
            dashboardViewModel.dataSource = .database
            await dashboardViewModel.refreshData()
        }
    }

    private func bootstrapDashboardIfNeeded(databaseClient: DatabaseClient) async {
        dashboardViewModel.isLoading = true
        dashboardViewModel.errorMessage = nil
        do {
            try await databaseClient.migrateIfNeeded()
            try await databaseClient.runScheduledRetentionPurgeIfNeeded()
            var metricsCount = try await databaseClient.productWeeklyMetricsCount()
            if metricsCount == 0, try await databaseClient.hasFactTableData() {
                try await databaseClient.rebuildProductWeeklyMetrics()
                metricsCount = try await databaseClient.productWeeklyMetricsCount()
            }
            dashboardViewModel.bootstrapDataSource(hasMetrics: metricsCount > 0)
            if metricsCount > 0 {
                await dashboardViewModel.refreshData()
            } else {
                dashboardViewModel.isLoading = false
            }
        } catch {
            dashboardViewModel.errorMessage = error.localizedDescription
            dashboardViewModel.isLoading = false
        }
    }
}
