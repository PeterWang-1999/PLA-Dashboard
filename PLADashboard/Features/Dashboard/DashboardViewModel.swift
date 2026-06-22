import Foundation
import Observation

@Observable
final class DashboardViewModel {
    var dataSource: DashboardDataSource = .preview
    var searchText = ""
    var selectedTimeDimension = "周维度"
    var selectedAccount = "全部账户"
    var selectedTag = "全部标签"
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
}
