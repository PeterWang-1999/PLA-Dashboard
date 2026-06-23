import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var dataSource: DashboardDataSource = .preview
    var searchText = ""
    var selectedAlertFilter = DashboardViewModel.alertFilterDefaultOption
    var customLabelCatalog: CustomLabelCatalog = .loadBundled()
    var selectedCustomLabelFilter: CustomLabelFilterSelection = .all
    var categoryCatalog: GoogleProductCategoryCatalog = .loadBundled()
    var selectedCategoryFilter: CategoryFilterSelection = .all
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

    static let alertFilterDefaultOption = "全部预警标签"
    static let alertFilterOptions = ["全部预警标签", "正常", "关注", "预警"]

    /// 已选择非默认筛选项，按钮文字使用 primary 样式。
    var isAlertFilterActive: Bool {
        selectedAlertFilter != Self.alertFilterDefaultOption
    }

    var isCustomLabelFilterActive: Bool {
        selectedCustomLabelFilter.isFiltered
    }

    /// 已选择具体类目（非「全部类目」）。
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
