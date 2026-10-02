import XCTest
@testable import PLADashboard

final class IncrementalWeeklyMetricsPerformanceTests: XCTestCase {
    /// 同一数据库配对测量；失效记录准备和导入解析不在计时内。
    func testSmallProductUpdateVersusFullRebuild() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 20_000, merchantRows: 1000)
        let file = try BenchmarkTestSupport.writeTemporaryFile(name: "incremental_update.csv", contents: BenchmarkTestSupport.makeAdsCSV(rowCount: 40, days: 4))
        defer { try? FileManager.default.removeItem(at: file) }
        let imported = try await AdsProductImporter(databaseClient: client).importFile(sourceURL: file) { _ in }
        try await measureRefresh(client: client, imported: imported, source: "ads")
    }

    func testSmallSalesUpdateVersusFullRebuild() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 20_000, merchantRows: 1000)
        let lines = ["日期,LSIN,Gross Sales($),毛利额($)"] + (1...10).map {
            "2026-06-15,S\(String(format: "%08d", $0)),100.00,30.00"
        }
        let file = try BenchmarkTestSupport.writeTemporaryFile(name: "incremental_sales.csv", contents: lines.joined(separator: "\n"))
        defer { try? FileManager.default.removeItem(at: file) }
        let imported = try await SalesReportImporter(databaseClient: client).importFile(sourceURL: file) { _ in }
        try await measureRefresh(client: client, imported: imported, source: "sales")
    }

    private func measureRefresh(client: DatabaseClient, imported: ImportResult, source: String) async throws {
        var full: [Double] = []
        var incremental: [Double] = []
        var marking: [Double] = []
        for iteration in 0..<12 {
            for useIncremental in [iteration.isMultiple(of: 2), !iteration.isMultiple(of: 2)] {
                let markStart = CFAbsoluteTimeGetCurrent()
                try await client.updateImportJob(imported.job)
                let markElapsed = (CFAbsoluteTimeGetCurrent() - markStart) * 1000
                let start = CFAbsoluteTimeGetCurrent()
                if useIncremental { try await client.refreshProductWeeklyMetricsAfterImport() }
                else { try await client.rebuildProductWeeklyMetrics() }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                if iteration > 0 {
                    if useIncremental { incremental.append(elapsed); marking.append(markElapsed) }
                    else { full.append(elapsed) }
                }
            }
        }
        // 基准也对照完整结果，不以“更快”代替正确性。
        let ids = (1...1000).map { String(format: "%08d", $0) }
        let weeks = ["2026-05-31", "2026-06-07", "2026-06-14", "2026-06-21"]
        try await client.updateImportJob(imported.job)
        try await client.refreshProductWeeklyMetricsAfterImport()
        let afterIncremental = try await client.fetchWeeklyMetrics(productIds: ids, weekStarts: weeks)
        try await client.rebuildProductWeeklyMetrics()
        let afterFull = try await client.fetchWeeklyMetrics(productIds: ids, weekStarts: weeks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func sorted(_ rows: [ProductWeeklyMetricsRecord]) -> [ProductWeeklyMetricsRecord] {
            rows.sorted { ($0.productId, $0.weekStart) < ($1.productId, $1.weekStart) }
        }
        XCTAssertEqual(try encoder.encode(sorted(afterIncremental)), try encoder.encode(sorted(afterFull)))
        full.sort(); incremental.sort(); marking.sort()
        let report = """
        WEEKLY_INCREMENTAL samples=11 facts=20000 products=1000 affectedProducts=10 updateFacts=\(imported.job.validRows) source=\(source) inMemory=true
        full_p50_ms=\(full[5]) full_p95_ms=\(full[10])
        incremental_p50_ms=\(incremental[5]) incremental_p95_ms=\(incremental[10])
        dirty_mark_p50_ms=\(marking[5]) dirty_mark_p95_ms=\(marking[10])
        """
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "weekly-incremental-\(source)-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
