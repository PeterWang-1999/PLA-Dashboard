import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var windowState: WindowState
    var accountKind: WorkspaceAccountKind = .thirdParty
    var onRequestDataUpdate: () -> Void = {}

    @State private var columnSortOrder = DashboardTableSort.default.columnSortOrder
    @State private var isPresentingExporter = false
    @State private var exportDocument = DashboardExportCSVDocument(
        bundle: DashboardExportBundle(rows: [], weekStarts: [], totalCount: 0),
        filters: DashboardQueryFilters(),
        includeClicksAndConversions: false
    )
    @State private var exportFilename = "pla-dashboard"
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var selectedProductIDs: Set<ProductPerformanceRowModel.ID> = []
    @State private var presentedProduct: ProductPerformanceRowModel?

    var body: some View {
        dashboardContent
            .navigationTitle("产品数据")
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
                guard viewModel.currentPage > 1,
                      !viewModel.isLoading,
                      !viewModel.isPaging else { return }
                viewModel.goToPreviousPage()
            }
            .focusedSceneValue(\.dashboardGoToFirstPage) {
                guard viewModel.currentPage > 1,
                      !viewModel.isLoading,
                      !viewModel.isPaging else { return }
                viewModel.goToFirstPage()
            }
            .focusedSceneValue(\.dashboardGoToNextPage) {
                guard viewModel.currentPage < viewModel.totalPages,
                      !viewModel.isLoading,
                      !viewModel.isPaging else { return }
                viewModel.goToNextPage()
            }
            .focusedSceneValue(\.dashboardGoToLastPage) {
                guard viewModel.currentPage < viewModel.totalPages,
                      !viewModel.isLoading,
                      !viewModel.isPaging else { return }
                viewModel.goToLastPage()
            }
            .focusedSceneValue(
                \.openSelectedProductDetail,
                openSelectedProductDetailAction
            )
            .sheet(item: $presentedProduct) { row in
                ProductDetailSheet(
                    summary: row,
                    reportingPeriodLabel: viewModel.reportingPeriodLabel,
                    loadDetail: { productID in
                        try await viewModel.fetchProductDetail(productID: productID)
                    }
                )
            }
            .onChange(of: accountKind) { _, newKind in
                if newKind != .thirdParty {
                    selectedProductIDs.removeAll()
                    presentedProduct = nil
                }
            }
            .fileExporter(
                isPresented: $isPresentingExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: exportFilename
            ) { _ in }
            .alert("无法导出", isPresented: $showExportError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(exportErrorMessage)
            }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if viewModel.showsErrorState, let message = viewModel.errorMessage {
            dashboardPlaceholderLayout {
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
            }
        } else if viewModel.showsEmptyState {
            dashboardPlaceholderLayout {
                DashboardEmptyStateView(onImport: onRequestDataUpdate)
            }
        } else if viewModel.isLoading, viewModel.rows.isEmpty {
            dashboardPlaceholderLayout {
                ProgressView("正在加载…")
                    .controlSize(.regular)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } else {
            ZStack(alignment: .top) {
                ProductPerformanceTable(
                    rows: viewModel.rows,
                    isSidebarVisible: windowState.isSidebarVisible,
                    sortOrder: $columnSortOrder,
                    selection: $selectedProductIDs,
                    onOpenProduct: openProductDetail
                )
                .disabled(viewModel.isLoading)
                .opacity(viewModel.isPaging ? 0.85 : 1)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var openSelectedProductDetailAction: (() -> Void)? {
        guard accountKind == .thirdParty,
              let productID = selectedProductIDs.first,
              viewModel.rows.contains(where: { $0.id == productID }) else {
            return nil
        }
        return { openProductDetail(productID) }
    }

    private func openProductDetail(_ productID: ProductPerformanceRowModel.ID) {
        guard accountKind == .thirdParty,
              let row = viewModel.rows.first(where: { $0.id == productID }) else {
            return
        }
        presentedProduct = row
    }

    /// 在 `safeAreaInset` 底栏之上的可用区域内垂直居中占位内容。
    @ViewBuilder
    private func dashboardPlaceholderLayout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dashboardFooter: some View {
        HStack(spacing: 12) {
            if viewModel.isLoading || viewModel.isPaging || viewModel.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        viewModel.isExporting
                            ? "正在导出"
                            : (viewModel.isPaging ? "正在翻页" : "正在加载")
                    )
            }

            if let period = viewModel.reportingPeriodLabel, !viewModel.showsEmptyState {
                Label(period, systemImage: "calendar.badge.clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(period)
            }

            Spacer()

            if !viewModel.showsEmptyState {
                Button("数据更新", action: onRequestDataUpdate)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Menu {
                Button("导出当前视图…") {
                    Task { await beginExport() }
                }
                .disabled(viewModel.isLoading || viewModel.isPaging || viewModel.isExporting || viewModel.showsEmptyState)
                Divider()
                Button("刷新聚合") {
                    Task { await viewModel.rebuildMetricsAndRefresh() }
                }
            } label: {
                Label("快捷操作", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .help("导出当前筛选结果或刷新聚合")

            DashboardMaintenanceMenu()

            if !viewModel.showsEmptyState {
                paginationControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button {
                    viewModel.goToFirstPage()
                } label: {
                    Image(systemName: "chevron.backward.to.line")
                }
                .disabled(viewModel.currentPage <= 1 || viewModel.isLoading || viewModel.isPaging)
                .help("首页")
                .accessibilityLabel("跳转到首页")
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button {
                    viewModel.goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(viewModel.currentPage <= 1 || viewModel.isLoading || viewModel.isPaging)
                .help("上一页")
                .accessibilityLabel("上一页")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            Text("第 \(viewModel.currentPage) / \(viewModel.totalPages) 页")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100)
                .accessibilityLabel("第 \(viewModel.currentPage) 页，共 \(viewModel.totalPages) 页")

            ControlGroup {
                Button {
                    viewModel.goToNextPage()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(viewModel.currentPage >= viewModel.totalPages || viewModel.isLoading || viewModel.isPaging)
                .help("下一页")
                .accessibilityLabel("下一页")
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button {
                    viewModel.goToLastPage()
                } label: {
                    Image(systemName: "chevron.forward.to.line")
                }
                .disabled(viewModel.currentPage >= viewModel.totalPages || viewModel.isLoading || viewModel.isPaging)
                .help("尾页")
                .accessibilityLabel("跳转到尾页")
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
        }
        .controlSize(.regular)
    }

    @MainActor
    private func beginExport() async {
        do {
            let document = try await viewModel.prepareExport(
                includeClicksAndConversions: !windowState.isSidebarVisible
            )
            exportDocument = document
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            exportFilename = "pla-dashboard-\(formatter.string(from: Date()))"
            isPresentingExporter = true
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }
}

#Preview("Empty State") {
    NavigationStack {
        DashboardView(
            viewModel: DashboardViewModel(),
            windowState: WindowState(isSidebarVisible: true)
        )
    }
    .frame(width: 783, height: 620)
}

#Preview("Sidebar Expanded") {
    NavigationStack {
        DashboardView(
            viewModel: {
                let model = DashboardViewModel()
                model.dataSource = .preview
                model.customLabelCatalog = .loadBundled()
                model.categoryCatalog = .loadBundled()
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
                model.customLabelCatalog = .loadBundled()
                model.categoryCatalog = .loadBundled()
                return model
            }(),
            windowState: WindowState(isSidebarVisible: false)
        )
    }
    .frame(width: 1033, height: 620)
}
