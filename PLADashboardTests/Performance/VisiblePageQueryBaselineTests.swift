import XCTest
@testable import PLADashboard

final class VisiblePageQueryBaselineTests: XCTestCase {
    /// 比较同一数据集上的查询工作量；不包含 SwiftUI、图片、渲染或搜索防抖。
    func testChartOnlyVersusRedundantPageAndChartWorkload() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 10_000, merchantRows: 500)
        let filters = DashboardQueryFilters()
        var chartOnly: [Double] = []
        var redundant: [Double] = []
        for index in 0..<12 {
            // 交替次序并清空应用计算缓存，降低固定先后顺序的偏差。
            for chartOnlyFirst in [index.isMultiple(of: 2), !index.isMultiple(of: 2)] {
                await client.invalidateDashboardCache()
                let start = CFAbsoluteTimeGetCurrent()
                if !chartOnlyFirst {
                    _ = try await client.fetchDashboardPage(filters: filters, page: 1, pageSize: 30)
                }
                let snapshot = try await client.fetchDataDashboard(filters: filters, accountKind: .thirdParty)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                XCTAssertFalse(snapshot.metrics.isEmpty)
                if index > 0 { // 第一轮仅预热，不计入样本。
                    if chartOnlyFirst { chartOnly.append(elapsed) } else { redundant.append(elapsed) }
                }
            }
        }
        let before = redundant.sorted()
        let after = chartOnly.sorted()
        func milliseconds(_ seconds: Double) -> String { String(format: "%.3f", seconds * 1_000) }
        let report = """
        VISIBLE_PAGE_BASELINE samples=11 adsRows=10000 merchantRows=500 inMemory=true
        redundant_p50_ms=\(milliseconds(before[5])) redundant_p95_ms=\(milliseconds(before[10]))
        chart_only_p50_ms=\(milliseconds(after[5])) chart_only_p95_ms=\(milliseconds(after[10]))
        """
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "visible-page-query-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
