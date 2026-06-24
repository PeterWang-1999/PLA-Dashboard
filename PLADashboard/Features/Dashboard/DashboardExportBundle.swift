import Foundation

struct DashboardExportBundle: Sendable {
    let rows: [ProductPerformanceRowModel]
    let weekStarts: [String]
    let totalCount: Int
}

enum DashboardExportError: Error, LocalizedError {
    case tooManyRows(Int, limit: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .tooManyRows(let count, let limit):
            return "筛选结果共 \(count) 行，超过导出上限 \(limit)。请缩小筛选范围后重试。"
        case .noData:
            return "没有可导出的数据。"
        }
    }
}
