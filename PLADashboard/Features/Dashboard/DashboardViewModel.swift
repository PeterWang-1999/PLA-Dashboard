import Foundation
import Observation

@Observable
final class DashboardViewModel {
    var dataSource: DashboardDataSource = .preview
    var searchText = ""
    var selectedAlertFilter = DashboardViewModel.alertFilterPlaceholder
    var selectedCustomLabel = DashboardViewModel.customLabelPlaceholder
    var categoryCatalog: GoogleProductCategoryCatalog = .loadBundled()
    var selectedCategoryFilter: CategoryFilterSelection = .none
    var currentPage = 1
    let pageSize = 30
    let totalPages = 10

    var rows: [ProductPerformanceRowModel] {
        switch dataSource {
        case .preview:
            filteredPreviewRows
        case .empty:
            []
        case .database:
            []
        }
    }

    var isEmpty: Bool { rows.isEmpty }

    private var filteredPreviewRows: [ProductPerformanceRowModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return DashboardPreviewData.rows }
        return DashboardPreviewData.rows.filter {
            $0.lsin.localizedCaseInsensitiveContains(query)
                || ($0.warningLabel.localizedCaseInsensitiveContains(query))
        }
    }

    func goToPreviousPage() {
        currentPage = max(1, currentPage - 1)
    }

    func goToNextPage() {
        currentPage = min(totalPages, currentPage + 1)
    }

    func refreshData() {
        // 阶段 2 接入导入与聚合后实现
    }

    static let alertFilterPlaceholder = "预警筛选"
    static let alertFilterValues = ["全部预警", "正常", "关注", "预警"]

    static let customLabelPlaceholder = "自定义标签筛选"
    static let customLabelValues = [
        "全部标签",
        "自定义标签 0",
        "自定义标签 1",
        "自定义标签 2",
        "自定义标签 3",
        "自定义标签 4",
    ]

    var isAlertFilterActive: Bool {
        selectedAlertFilter != Self.alertFilterPlaceholder
    }

    var isCustomLabelFilterActive: Bool {
        selectedCustomLabel != Self.customLabelPlaceholder
    }

    var isCategoryFilterActive: Bool {
        selectedCategoryFilter.isActive
    }

    func reloadCategoryCatalog(from tsvURL: URL) throws {
        categoryCatalog = try GoogleProductCategoryCatalog.parse(from: tsvURL)
        selectedCategoryFilter = .none
    }
}
