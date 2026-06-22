import SwiftUI

struct RootView: View {
    @Environment(\.databaseClient) private var databaseClient
    @SceneStorage("dashboard.sidebarVisible") private var sidebarVisibleStorage = true

    @State private var windowState = WindowState()
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var selectedNavigationItem: AppNavigationItem? = .dashboard

    var body: some View {
        NavigationSplitView(columnVisibility: $windowState.columnVisibility) {
            sidebar
        } detail: {
            detailContent
                .focusedSceneValue(\.windowState, windowState)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        .onAppear {
            windowState.syncFromSceneStorage(sidebarVisibleStorage)
        }
        .onChange(of: windowState.columnVisibility) { _, visibility in
            windowState.isSidebarVisible = visibility != .detailOnly
            sidebarVisibleStorage = windowState.isSidebarVisible
        }
        .task {
            await bootstrapDatabaseIfNeeded()
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
            DashboardView(viewModel: dashboardViewModel, windowState: windowState)
        case .imports:
            ContentUnavailableView("数据导入", systemImage: "square.and.arrow.down", description: Text("阶段 2 实现"))
        case .settings:
            ContentUnavailableView("设置", systemImage: "gearshape", description: Text("阶段 6 实现"))
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
