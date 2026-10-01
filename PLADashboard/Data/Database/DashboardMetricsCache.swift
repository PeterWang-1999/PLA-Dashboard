import Foundation

/// 看板整体指标缓存（同一报告窗口内复用）。
struct DashboardMetricsCache: Sendable {
    let weekStartsKey: String
    /// 表格指标、相对整体变化和排序使用 6 个完整周 + 当前周。
    let overallBenchmark: AggregatedMetrics
    let totalCostCents: Int
}

extension Array where Element == String {
    var cacheKey: String {
        joined(separator: "|")
    }
}
