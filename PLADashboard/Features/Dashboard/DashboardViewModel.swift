import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var dataSource: DashboardDataSource = .empty
    var searchText = ""
    var selectedAlertFilter = DashboardViewModel.alertFilterDefaultOption
    var customLabelCatalog: CustomLabelCatalog = .empty
    var selectedCustomLabelFilter: CustomLabelFilterSelection = .all
    var categoryCatalog: GoogleProductCategoryCatalog = .empty
    var selectedCategoryFilter: CategoryFilterSelection = .all
    var currentPage = 1
    var pageSize: Int { AppSettings.defaultPageSize }
    var totalPages = 1
    /// 当前展示数据周期；若含未完成周，会同时说明截止日与覆盖天数。
    var reportingPeriodLabel: String?
    private(set) var reportingWeekStarts: [String] = []
    private(set) var latestDataDay: String?
    var isLoading = false
    /// 仅翻页时的轻量加载，不整表禁用、不盖全屏转圈。
    var isPaging = false
    var errorMessage: String?
    var tableSort = DashboardTableSort.default
    var dataDashboardSnapshot = DataDashboardSnapshot.empty
    var isLoadingDataDashboard = false
    var dataDashboardErrorMessage: String?

    private var databaseClient: DatabaseClient?
    @ObservationIgnored private let followsVisiblePage: Bool
    private(set) var visiblePage: AppNavigationItem = .dashboard

    /// 导航隐藏页面时立即使其请求失效；返回时按当前筛选重新加载。
    func setVisiblePage(_ page: AppNavigationItem) {
        guard visiblePage != page else { return }
        visiblePage = page
        invalidateTableRequest()
        chartRequestID &+= 1
        isLoadingDataDashboard = false
        if dataSource == .database { scheduleRefresh() }
    }

    func cancelVisibleRefresh() {
        invalidateTableRequest()
        chartRequestID &+= 1
        isLoadingDataDashboard = false
    }

    private func refreshVisiblePage() async {
        if followsVisiblePage, visiblePage == .imports { return }
        if followsVisiblePage, visiblePage == .dataDashboard {
            await refreshDataDashboard()
        } else {
            await refreshData()
        }
    }
    private var databaseRows: [ProductPerformanceRowModel] = []
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var tableRequestID: UInt = 0
    private var chartRequestID: UInt = 0
    @ObservationIgnored private let pageLoader: PageLoader
    @ObservationIgnored private let chartLoader: ChartLoader
    @ObservationIgnored private let exportLoader: ExportLoader
    @ObservationIgnored private let exportBuilder = DashboardExportBuilder()
    private var exportRequestID: UInt = 0
    var exportWorkspaceGeneration: UInt { loadGeneration }

    typealias ExportLoader = @Sendable (DatabaseClient, DashboardQueryFilters) async throws -> DashboardExportBundle

    typealias PageLoader = @Sendable (DatabaseClient, DashboardQueryFilters, Int, Int) async throws -> DashboardPageResult
    typealias ChartLoader = @Sendable (DatabaseClient, DashboardQueryFilters, WorkspaceAccountKind) async throws -> DataDashboardSnapshot

    init(
        followsVisiblePage: Bool = false,
        pageLoader: @escaping PageLoader = { client, filters, page, size in
            try await client.fetchDashboardPage(filters: filters, page: page, pageSize: size)
        },
        chartLoader: @escaping ChartLoader = { client, filters, kind in
            try await client.fetchDataDashboard(filters: filters, accountKind: kind)
        },
        exportLoader: @escaping ExportLoader = { client, filters in
            try await client.fetchDashboardAllRows(filters: filters)
        }
    ) {
        self.followsVisiblePage = followsVisiblePage
        self.pageLoader = pageLoader
        self.chartLoader = chartLoader
        self.exportLoader = exportLoader
    }
    /// 每次账户切换递增，用于丢弃过期的异步加载结果。
    private var loadGeneration: UInt = 0
    private(set) var warningLabelEngine: WarningLabelEngine = .thirdPartyCohort
    private(set) var accountKind: WorkspaceAccountKind = .thirdParty

    var rows: [ProductPerformanceRowModel] {
        switch dataSource {
        case .preview:
            filteredPreviewRows
        case .empty, .database:
            databaseRows
        }
    }

    var showsEmptyState: Bool {
        dataSource == .empty && !isLoading && errorMessage == nil
    }

    var showsErrorState: Bool {
        errorMessage != nil && !isLoading
    }

    var isEmpty: Bool { rows.isEmpty }

    private var bootstrapAction: (() async -> Void)?

    private var filteredPreviewRows: [ProductPerformanceRowModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [ProductPerformanceRowModel]
        if query.isEmpty {
            base = DashboardPreviewData.rows
        } else {
            base = DashboardPreviewData.rows.filter {
                $0.lsin.localizedCaseInsensitiveContains(query)
                    || $0.warningLabel.localizedCaseInsensitiveContains(query)
            }
        }
        return base.sorted { tableSort.sortsBefore($0, $1) }
    }

    func configure(
        databaseClient: DatabaseClient,
        accountKind: WorkspaceAccountKind = .thirdParty,
        bootstrap: @escaping () async -> Void = {}
    ) {
        self.databaseClient = databaseClient
        self.accountKind = accountKind
        self.bootstrapAction = bootstrap
        warningLabelEngine = WarningLabelEngine.forAccountKind(accountKind)
        if !alertFilterOptions.contains(selectedAlertFilter) {
            selectedAlertFilter = Self.alertFilterDefaultOption
        }
    }

    func resetForAccountSwitch() {
        loadGeneration &+= 1
        exportRequestID &+= 1
        invalidateTableRequest()
        retryTask?.cancel()
        retryTask = nil
        settingsTask?.cancel()
        settingsTask = nil
        chartRequestID &+= 1
        searchText = ""
        selectedAlertFilter = Self.alertFilterDefaultOption
        selectedCustomLabelFilter = .all
        selectedCategoryFilter = .all
        currentPage = 1
        totalPages = 1
        reportingPeriodLabel = nil
        reportingWeekStarts = []
        latestDataDay = nil
        tableSort = .default
        dataDashboardSnapshot = .empty
        isLoadingDataDashboard = false
        dataDashboardErrorMessage = nil
        databaseRows = []
        dataSource = .empty
        errorMessage = nil
        isLoading = false
        isPaging = false
        isExporting = false
        exportErrorMessage = nil
        categoryCatalog = .empty
        customLabelCatalog = .empty
        warningLabelEngine = .thirdPartyCohort
    }

    func retryAfterError() {
        retryTask?.cancel()
        guard dataSource == .empty, let bootstrapAction else {
            scheduleRefresh()
            return
        }
        let requestID = invalidateTableRequest()
        let generation = loadGeneration
        retryTask = Task { @MainActor in
            guard !Task.isCancelled, generation == loadGeneration, requestID == tableRequestID else { return }
            errorMessage = nil
            await bootstrapAction()
        }
    }

    func bootstrapDashboard() async {
        let generation = loadGeneration
        guard let databaseClient else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await databaseClient.migrateIfNeeded()
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }

            try await databaseClient.runScheduledRetentionPurgeIfNeeded()
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }

            var metricsCount = try await databaseClient.productWeeklyMetricsCount()
            if metricsCount == 0, try await databaseClient.hasFactTableData() {
                try await databaseClient.rebuildProductWeeklyMetrics()
                metricsCount = try await databaseClient.productWeeklyMetricsCount()
            }

            try Task.checkCancellation()
            guard generation == loadGeneration else { return }

            bootstrapDataSource(hasMetrics: metricsCount > 0)
            if metricsCount > 0 {
                isLoading = false
                await refreshVisiblePage()
            } else {
                guard generation == loadGeneration else { return }
                isLoading = false
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func handleImportCompleted() async {
        dataSource = .database
        cancelVisibleRefresh()
        await refreshVisiblePage()
    }

    func bootstrapDataSource(hasMetrics: Bool) {
        guard dataSource != .preview else { return }
        dataSource = hasMetrics ? .database : .empty
    }

    func goToPreviousPage() {
        guard currentPage > 1 else { return }
        currentPage -= 1
        scheduleRefresh(mode: .paging)
    }

    func goToFirstPage() {
        guard currentPage > 1 else { return }
        currentPage = 1
        scheduleRefresh(mode: .paging)
    }

    func goToNextPage() {
        guard currentPage < totalPages else { return }
        currentPage += 1
        scheduleRefresh(mode: .paging)
    }

    func goToLastPage() {
        guard currentPage < totalPages else { return }
        currentPage = totalPages
        scheduleRefresh(mode: .paging)
    }

    func onSearchTextChanged() {
        currentPage = 1
        scheduleRefresh(mode: .full, debounce: .milliseconds(250))
    }

    func onFiltersChanged() {
        currentPage = 1
        scheduleRefresh(mode: .full)
    }

    func refreshDataDashboard() async {
        guard !Task.isCancelled, !followsVisiblePage || visiblePage == .dataDashboard else { return }
        chartRequestID &+= 1
        let requestID = chartRequestID
        let generation = loadGeneration
        let filters = makeCurrentFilters()
        let kind = accountKind
        defer {
            if generation == loadGeneration, requestID == chartRequestID {
                isLoadingDataDashboard = false
            }
        }
        guard dataSource == .database, let databaseClient else {
            dataDashboardSnapshot = .empty
            return
        }
        isLoadingDataDashboard = true
        dataDashboardErrorMessage = nil
        do {
            let snapshot = try await chartLoader(databaseClient, filters, kind)
            guard !Task.isCancelled, generation == loadGeneration, requestID == chartRequestID,
                  filters == makeCurrentFilters(), kind == accountKind else { return }
            dataDashboardSnapshot = snapshot
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == loadGeneration, requestID == chartRequestID,
                  filters == makeCurrentFilters(), kind == accountKind else { return }
            dataDashboardErrorMessage = error.localizedDescription
        }
    }

    func setTableSort(_ sort: DashboardTableSort) {
        guard tableSort != sort else { return }
        tableSort = sort
        currentPage = 1
        if dataSource == .preview {
            return
        }
        scheduleRefresh(mode: .full)
    }

    func applyColumnSort(_ order: [KeyPathComparator<ProductPerformanceRowModel>]) {
        guard let sort = DashboardTableSort.from(columnSortOrder: order) else { return }
        setTableSort(sort)
    }

    var columnSortOrder: [KeyPathComparator<ProductPerformanceRowModel>] {
        tableSort.columnSortOrder
    }

    enum RefreshMode {
        case full
        case paging
    }

    @discardableResult
    private func invalidateTableRequest() -> UInt {
        refreshTask?.cancel()
        refreshTask = nil
        tableRequestID &+= 1
        isLoading = false
        isPaging = false
        return tableRequestID
    }

    func scheduleRefresh(mode: RefreshMode = .full, debounce: Duration = .zero) {
        let requestID = invalidateTableRequest()
        chartRequestID &+= 1
        isLoadingDataDashboard = false
        guard !followsVisiblePage || visiblePage != .imports else { return }
        let generation = loadGeneration
        let page = visiblePage
        refreshTask = Task { @MainActor in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
            } catch { return }
            guard !Task.isCancelled, generation == loadGeneration,
                  !followsVisiblePage || page == visiblePage else { return }
            if followsVisiblePage, page == .dataDashboard {
                await refreshDataDashboard()
            } else {
                await refreshData(mode: mode, requestID: requestID, generation: generation)
            }
        }
    }

    func refreshData(mode: RefreshMode = .full) async {
        guard !Task.isCancelled else { return }
        let requestID = invalidateTableRequest()
        await refreshData(mode: mode, requestID: requestID, generation: loadGeneration)
    }

    private func refreshData(mode: RefreshMode, requestID: UInt, generation: UInt) async {
        guard !Task.isCancelled, generation == loadGeneration, requestID == tableRequestID,
              !followsVisiblePage || visiblePage == .dashboard else { return }
        guard dataSource == .database, let databaseClient else { return }
        let filters = makeCurrentFilters()
        let requestedPage = currentPage
        let requestedSize = pageSize
        defer {
            if generation == loadGeneration, requestID == tableRequestID {
                isLoading = false
                isPaging = false
            }
        }
        switch mode {
        case .full:
            isLoading = true
            isPaging = false
        case .paging:
            isPaging = true
        }
        errorMessage = nil

        do {
            let result = try await pageLoader(databaseClient, filters, requestedPage, requestedSize)
            guard !Task.isCancelled, generation == loadGeneration, requestID == tableRequestID,
                  filters == makeCurrentFilters(), requestedPage == currentPage,
                  requestedSize == pageSize else { return }
            databaseRows = result.rows
            totalPages = result.totalPages
            reportingPeriodLabel = WeekCalendar.dashboardDataPeriodLabel(
                weekStarts: result.weekStarts,
                latestDay: result.latestDataDay
            )
            reportingWeekStarts = result.weekStarts
            latestDataDay = result.latestDataDay
            if currentPage > totalPages {
                currentPage = totalPages
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == loadGeneration, requestID == tableRequestID,
                  filters == makeCurrentFilters(), requestedPage == currentPage,
                  requestedSize == pageSize else { return }
            errorMessage = error.localizedDescription
            databaseRows = []
            totalPages = 1
            reportingPeriodLabel = nil
            reportingWeekStarts = []
            latestDataDay = nil
        }
    }

    func rebuildMetricsAndRefresh(onDataChanged: (() -> Void)? = nil) async {
        let generation = loadGeneration
        guard let databaseClient else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await databaseClient.rebuildProductWeeklyMetrics()
            guard generation == loadGeneration else { return }
            isLoading = false
            if let onDataChanged {
                onDataChanged()
                return
            }
            dataSource = .database
            await reloadFilterCatalogsFromDatabase()
            guard generation == loadGeneration else { return }
            cancelVisibleRefresh()
            await refreshVisiblePage()
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    static let alertFilterDefaultOption = DashboardQueryFilters.alertFilterDefaultOption

    var alertFilterOptions: [String] {
        let cases: [ProductWarningLabel]
        switch warningLabelEngine {
        case .thirdPartyCohort:
            cases = ProductWarningLabel.thirdPartyFilterCases
        case .selfBuiltSnapshot:
            cases = ProductWarningLabel.selfBuiltFilterCases
        }
        return [Self.alertFilterDefaultOption] + cases.map(\.rawValue)
    }

    var isAlertFilterActive: Bool {
        selectedAlertFilter != Self.alertFilterDefaultOption
    }

    var isCustomLabelFilterActive: Bool {
        selectedCustomLabelFilter.isFiltered
    }

    var isCategoryFilterActive: Bool {
        selectedCategoryFilter.isFiltered
    }

    func reloadFilterCatalogsFromDatabase() async {
        let generation = loadGeneration
        guard let databaseClient else { return }
        do {
            let snapshot = try await databaseClient.buildFilterCatalogSnapshot()
            guard generation == loadGeneration else { return }
            applyFilterCatalogSnapshot(snapshot)
        } catch {
            guard generation == loadGeneration else { return }
            clearFilterCatalogs()
        }
    }

    private func clearFilterCatalogs() {
        categoryCatalog = .empty
        customLabelCatalog = .empty
        selectedCategoryFilter = .all
        selectedCustomLabelFilter = .all
    }

    /// 当前账户尚无 Merchant 产品数据时，用于 Toolbar 空态提示（HIG empty state）。
    var customLabelFilterEmptyHelp: String? {
        guard dataSource != .preview else { return nil }
        let hasValues = customLabelCatalog.groups.contains(where: \.hasValueChildren)
        return hasValues ? nil : "请先在当前账户导入 Merchant Center 数据以显示标签选项"
    }

    var categoryFilterEmptyHelp: String? {
        guard dataSource != .preview else { return nil }
        return categoryCatalog.groups.isEmpty
            ? "请先在当前账户导入 Merchant Center 数据以显示类目选项"
            : nil
    }

    func applyFilterCatalogSnapshot(_ snapshot: DatabaseClient.FilterCatalogSnapshot) {
        categoryCatalog = snapshot.categoryCatalog
        customLabelCatalog = snapshot.customLabelCatalog
        selectedCategoryFilter = .all
        selectedCustomLabelFilter = .all
    }

    var isExporting = false
    var exportErrorMessage: String?

    func makeCurrentFilters() -> DashboardQueryFilters {
        DashboardQueryFilters(
            searchText: searchText,
            alertFilter: selectedAlertFilter,
            customLabelFilter: selectedCustomLabelFilter,
            categoryFilter: selectedCategoryFilter,
            sort: tableSort,
            warningLabelEngine: warningLabelEngine
        )
    }

    func prepareExport(includeClicksAndConversions: Bool) async throws -> DashboardExportCSVDocument {
        guard dataSource == .database, let databaseClient else {
            throw DashboardExportError.noData
        }
        let generation = loadGeneration
        let filters = makeCurrentFilters()
        exportRequestID &+= 1
        let requestID = exportRequestID
        isExporting = true
        exportErrorMessage = nil
        defer {
            if requestID == exportRequestID { isExporting = false }
        }

        do {
            let bundle = try await exportLoader(databaseClient, filters)
            try Task.checkCancellation()
            guard generation == loadGeneration, requestID == exportRequestID else {
                throw CancellationError()
            }
            guard !bundle.rows.isEmpty else { throw DashboardExportError.noData }
            let document = try await exportBuilder.build(
                bundle: bundle,
                filters: filters,
                includeClicksAndConversions: includeClicksAndConversions
            )
            try Task.checkCancellation()
            guard generation == loadGeneration, requestID == exportRequestID else {
                throw CancellationError()
            }
            return document
        } catch {
            guard !Task.isCancelled, generation == loadGeneration, requestID == exportRequestID else {
                throw CancellationError()
            }
            throw error
        }
    }

    func fetchProductDetail(productID: String) async throws -> ProductDetailModel {
        guard accountKind == .thirdParty else {
            throw ProductDetailError.unsupportedAccount
        }
        guard let databaseClient,
              !reportingWeekStarts.isEmpty,
              let latestDataDay else {
            throw ProductDetailError.missingReportingPeriod
        }
        return try await databaseClient.fetchProductDetail(
            productID: productID,
            weekStarts: reportingWeekStarts,
            latestDataDay: latestDataDay
        )
    }

    func handleSettingsDidChange() {
        guard databaseClient != nil else { return }
        cancelVisibleRefresh()
        settingsTask?.cancel()
        let generation = loadGeneration
        settingsTask = Task { @MainActor in
            guard !Task.isCancelled, generation == loadGeneration, let databaseClient else { return }
            await databaseClient.invalidateDashboardCache()
            guard !Task.isCancelled, generation == loadGeneration else { return }
            if dataSource == .database {
                scheduleRefresh()
            }
        }
    }
}
