import Foundation

/// 看板整体指标缓存（同一报告窗口内复用）。
struct DashboardMetricsCache: Sendable {
    let weekStartsKey: String
    let overallWeeks: [WeeklyProductMetrics]
    let cohortBenchmarks: [WeeklyCohortSpendBenchmark]
    let overallBenchmark: AggregatedMetrics
    let totalCostCents: Int
}

extension Array where Element == String {
    var cacheKey: String {
        joined(separator: "|")
    }
}
