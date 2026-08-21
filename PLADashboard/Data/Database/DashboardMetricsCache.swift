import Foundation

/// 看板整体指标缓存（同一报告窗口内复用）。
struct DashboardMetricsCache: Sendable {
    let weekStartsKey: String
    /// 预警标签仍仅使用 6 个完整周。
    let overallWeeks: [WeeklyProductMetrics]
    let cohortBenchmarks: [WeeklyCohortSpendBenchmark]
    /// 表格指标、相对整体变化和排序使用 6 个完整周 + 当前周。
    let overallBenchmark: AggregatedMetrics
    let totalCostCents: Int
    let warningTotalCostCents: Int
}

extension Array where Element == String {
    var cacheKey: String {
        joined(separator: "|")
    }
}
