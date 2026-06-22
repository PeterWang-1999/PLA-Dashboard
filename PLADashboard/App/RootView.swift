import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.databaseClient) private var databaseClient
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
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .fileImporter(
            isPresented: $importViewModel.showFileImporter,
            allowedContentTypes: [.tabSeparatedText],
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
            configureImportViewModelIfNeeded()
        }
        .onChange(of: windowState.columnVisibility) { _, visibility in
            windowState.isSidebarVisible = visibility != .detailOnly
            sidebarVisibleStorage = windowState.isSidebarVisible
        }
        .onChange(of: databaseClient != nil) { _, _ in
            configureImportViewModelIfNeeded()
        }
        .task {
            await bootstrapDatabaseIfNeeded()
            configureImportViewModelIfNeeded()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedNavigationItem) {
            Section("导航") {
                ForEach(AppNavigationItem.allCases) { item in
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
            ContentUnavailableView("设置", systemImage: "gearshape", description: Text("阶段 6 实现"))
        }
    }

    private func configureImportViewModelIfNeeded() {
        guard let databaseClient else { return }
        importViewModel.configure(databaseClient: databaseClient) { url in
            try? dashboardViewModel.reloadFilterCatalogs(from: url)
        }
    }

    private func bootstrapDatabaseIfNeeded() async {
        guard let databaseClient else { return }
        do {
            try await databaseClient.migrateIfNeeded()
            let count = try await databaseClient.productWeeklyMetricsCount()
            if count == 0 && dashboardViewModel.dataSource == .database {
                dashboardViewModel.dataSource = .empty
            }
        } catch {
            #if DEBUG
            print("Database bootstrap failed: \(error)")
            #endif
        }
    }
}
