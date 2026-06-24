import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var windowState: WindowState
    var onRequestDataUpdate: () -> Void = {}

    @State private var columnSortOrder = DashboardTableSort.default.columnSortOrder

    var body: some View {
        dashboardContent
            .navigationTitle("产品数据")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                DashboardToolbarContent(viewModel: viewModel)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dashboardFooter
                    .background(.bar)
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .toolbar,
                prompt: "输入产品 ID 查询"
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.onSearchTextChanged()
            }
            .onChange(of: viewModel.selectedAlertFilter) { _, _ in
                viewModel.onFiltersChanged()
            }
            .onChange(of: viewModel.selectedCustomLabelFilter) { _, _ in
                viewModel.onFiltersChanged()
            }
            .onChange(of: viewModel.selectedCategoryFilter) { _, _ in
                viewModel.onFiltersChanged()
            }
            .onChange(of: columnSortOrder) { _, newOrder in
                if DashboardTableSort.from(columnSortOrder: newOrder) != nil {
                    viewModel.applyColumnSort(newOrder)
                } else {
                    columnSortOrder = viewModel.columnSortOrder
                }
            }
            .onChange(of: viewModel.tableSort) { _, _ in
                columnSortOrder = viewModel.columnSortOrder
            }
            .focusedSceneValue(\.dashboardGoToPreviousPage) {
                guard viewModel.currentPage > 1, !viewModel.isLoading else { return }
                viewModel.goToPreviousPage()
            }
            .focusedSceneValue(\.dashboardGoToNextPage) {
                guard viewModel.currentPage < viewModel.totalPages, !viewModel.isLoading else { return }
                viewModel.goToNextPage()
            }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if viewModel.showsErrorState, let message = viewModel.errorMessage {
            ContentUnavailableView {
                Label("无法加载看板数据", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    viewModel.retryAfterError()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.showsEmptyState {
            DashboardEmptyStateView(onImport: onRequestDataUpdate)
        } else if viewModel.isLoading, viewModel.rows.isEmpty {
            ProgressView("正在加载…")
                .controlSize(.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            ZStack(alignment: .top) {
                ProductPerformanceTable(
                    rows: viewModel.rows,
                    isSidebarVisible: windowState.isSidebarVisible,
                    sortOrder: $columnSortOrder
                )
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .accessibilityLabel("正在刷新数据")
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var dashboardFooter: some View {
        HStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在加载")
            }

            Spacer()

            Button("数据更新", action: onRequestDataUpdate)
                .buttonStyle(.bordered)
                .controlSize(.large)

            Menu {
                Button("导出当前视图（阶段 6 实现）") {}
                    .disabled(true)
                Divider()
                Button("刷新聚合") {
                    Task { await viewModel.rebuildMetricsAndRefresh() }
                }
            } label: {
                Label("快捷操作", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .help("刷新聚合；导出功能将在阶段 6 提供")

            paginationControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.currentPage <= 1 || viewModel.isLoading)
            .help("上一页")
            .accessibilityLabel("上一页")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Text("第 \(viewModel.currentPage) / \(viewModel.totalPages) 页")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100)
                .accessibilityLabel("第 \(viewModel.currentPage) 页，共 \(viewModel.totalPages) 页")

            Button {
                viewModel.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.currentPage >= viewModel.totalPages || viewModel.isLoading)
            .help("下一页")
            .accessibilityLabel("下一页")
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .controlSize(.large)
    }
}

#Preview("Sidebar Expanded") {
    NavigationStack {
        DashboardView(
            viewModel: {
                let model = DashboardViewModel()
                model.dataSource = .preview
                return model
            }(),
            windowState: WindowState(isSidebarVisible: true)
        )
    }
    .frame(width: 783, height: 620)
}

#Preview("Sidebar Collapsed") {
    NavigationStack {
        DashboardView(
            viewModel: {
                let model = DashboardViewModel()
                model.dataSource = .preview
                return model
            }(),
            windowState: WindowState(isSidebarVisible: false)
        )
    }
    .frame(width: 1033, height: 620)
}
