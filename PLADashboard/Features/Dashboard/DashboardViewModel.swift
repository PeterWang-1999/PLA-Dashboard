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

    private var databaseClient: DatabaseClient?
    private var databaseRows: [ProductPerformanceRowModel] = []
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
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
        searchTask?.cancel()
        refreshTask?.cancel()
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
        refreshTask?.cancel()
        let generation = loadGeneration
        refreshTask = Task { @MainActor in
            guard generation == loadGeneration else { return }
            errorMessage = nil
            if dataSource == .empty, let bootstrapAction {
                await bootstrapAction()
            } else {
                await refreshData()
            }
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
                await refreshData()
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
        let generation = loadGeneration
        guard generation == loadGeneration else { return }
        dataSource = .database
        await refreshData()
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
        searchTask?.cancel()
        let generation = loadGeneration
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, generation == loadGeneration else { return }
            await refreshData(mode: .full)
        }
    }

    func onFiltersChanged() {
        currentPage = 1
        scheduleRefresh(mode: .full)
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

    func scheduleRefresh(mode: RefreshMode = .full) {
        refreshTask?.cancel()
        let generation = loadGeneration
        refreshTask = Task { @MainActor in
            guard generation == loadGeneration else { return }
            await refreshData(mode: mode)
        }
    }

    func refreshData(mode: RefreshMode = .full) async {
        let generation = loadGeneration
        guard dataSource == .database, let databaseClient else { return }
        switch mode {
        case .full:
            isLoading = true
            isPaging = false
        case .paging:
            isPaging = true
        }
        errorMessage = nil

        do {
            let filters = DashboardQueryFilters(
                searchText: searchText,
                alertFilter: selectedAlertFilter,
                customLabelFilter: selectedCustomLabelFilter,
                categoryFilter: selectedCategoryFilter,
                sort: tableSort,
                warningLabelEngine: warningLabelEngine
            )
            let result = try await databaseClient.fetchDashboardPage(
                filters: filters,
                page: currentPage,
                pageSize: pageSize
            )
            guard generation == loadGeneration else { return }
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
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            databaseRows = []
            totalPages = 1
            reportingPeriodLabel = nil
            reportingWeekStarts = []
            latestDataDay = nil
        }

        guard generation == loadGeneration else { return }
        isLoading = false
        isPaging = false
    }

    func rebuildMetricsAndRefresh() async {
        let generation = loadGeneration
        guard let databaseClient else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await databaseClient.rebuildProductWeeklyMetrics()
            guard generation == loadGeneration else { return }
            dataSource = .database
            await reloadFilterCatalogsFromDatabase()
            guard generation == loadGeneration else { return }
            await refreshData()
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
        isExporting = true
        exportErrorMessage = nil
        defer { isExporting = false }

        let bundle = try await databaseClient.fetchDashboardAllRows(filters: makeCurrentFilters())
        guard !bundle.rows.isEmpty else {
            throw DashboardExportError.noData
        }
        return DashboardExportCSVDocument(
            bundle: bundle,
            filters: makeCurrentFilters(),
            includeClicksAndConversions: includeClicksAndConversions
        )
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
        let generation = loadGeneration
        Task { @MainActor in
            guard generation == loadGeneration, let databaseClient else { return }
            await databaseClient.invalidateDashboardCache()
            guard generation == loadGeneration else { return }
            if dataSource == .database {
                await refreshData()
            }
        }
    }
}
