import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var dataSource: DashboardDataSource = .empty
    var searchText = ""
    var selectedAlertFilter = DashboardViewModel.alertFilterDefaultOption
    var customLabelCatalog: CustomLabelCatalog = .loadBundled()
    var selectedCustomLabelFilter: CustomLabelFilterSelection = .all
    var categoryCatalog: GoogleProductCategoryCatalog = .loadBundled()
    var selectedCategoryFilter: CategoryFilterSelection = .all
    var currentPage = 1
    var pageSize: Int { AppSettings.defaultPageSize }
    var totalPages = 1
    var isLoading = false
    var errorMessage: String?
    var tableSort = DashboardTableSort.default

    private var databaseClient: DatabaseClient?
    private var databaseRows: [ProductPerformanceRowModel] = []
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

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
        bootstrap: @escaping () async -> Void = {}
    ) {
        self.databaseClient = databaseClient
        self.bootstrapAction = bootstrap
    }

    func retryAfterError() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            errorMessage = nil
            if dataSource == .empty, let bootstrapAction {
                await bootstrapAction()
            } else {
                await refreshData()
            }
        }
    }

    func bootstrapDataSource(hasMetrics: Bool) {
        guard dataSource != .preview else { return }
        dataSource = hasMetrics ? .database : .empty
    }

    func goToPreviousPage() {
        guard currentPage > 1 else { return }
        currentPage -= 1
        scheduleRefresh()
    }

    func goToNextPage() {
        guard currentPage < totalPages else { return }
        currentPage += 1
        scheduleRefresh()
    }

    func onSearchTextChanged() {
        currentPage = 1
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await refreshData()
        }
    }

    func onFiltersChanged() {
        currentPage = 1
        scheduleRefresh()
    }

    func setTableSort(_ sort: DashboardTableSort) {
        guard tableSort != sort else { return }
        tableSort = sort
        currentPage = 1
        if dataSource == .preview {
            return
        }
        scheduleRefresh()
    }

    func applyColumnSort(_ order: [KeyPathComparator<ProductPerformanceRowModel>]) {
        guard let sort = DashboardTableSort.from(columnSortOrder: order) else { return }
        setTableSort(sort)
    }

    var columnSortOrder: [KeyPathComparator<ProductPerformanceRowModel>] {
        tableSort.columnSortOrder
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await refreshData()
        }
    }

    func refreshData() async {
        guard dataSource == .database, let databaseClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let filters = DashboardQueryFilters(
                searchText: searchText,
                alertFilter: selectedAlertFilter,
                customLabelFilter: selectedCustomLabelFilter,
                categoryFilter: selectedCategoryFilter,
                sort: tableSort
            )
            let result = try await databaseClient.fetchDashboardPage(
                filters: filters,
                page: currentPage,
                pageSize: pageSize
            )
            databaseRows = result.rows
            totalPages = result.totalPages
            if currentPage > totalPages {
                currentPage = totalPages
            }
        } catch {
            errorMessage = error.localizedDescription
            databaseRows = []
        }

        isLoading = false
    }

    func rebuildMetricsAndRefresh() async {
        guard let databaseClient else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await databaseClient.rebuildProductWeeklyMetrics()
            dataSource = .database
            await refreshData()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    static let alertFilterDefaultOption = DashboardQueryFilters.alertFilterDefaultOption
    static let alertFilterOptions = [
        alertFilterDefaultOption,
        ProductWarningLabel.highSpendHighEfficiency.rawValue,
        ProductWarningLabel.highSpendLowEfficiency.rawValue,
        ProductWarningLabel.lowSpend.rawValue,
        ProductWarningLabel.highSpend.rawValue,
        ProductWarningLabel.lowEfficiency.rawValue,
    ]

    var isAlertFilterActive: Bool {
        selectedAlertFilter != Self.alertFilterDefaultOption
    }

    var isCustomLabelFilterActive: Bool {
        selectedCustomLabelFilter.isFiltered
    }

    var isCategoryFilterActive: Bool {
        selectedCategoryFilter.isFiltered
    }

    func reloadFilterCatalogs(from tsvURL: URL) throws {
        categoryCatalog = try GoogleProductCategoryCatalog.parse(from: tsvURL)
        customLabelCatalog = try CustomLabelCatalog.parse(from: tsvURL)
        selectedCategoryFilter = .all
        selectedCustomLabelFilter = .all
    }
}
