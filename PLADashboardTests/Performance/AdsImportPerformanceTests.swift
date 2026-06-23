import XCTest
@testable import PLADashboard

/// 阶段 5 性能基准（默认 10k 行；`PLA_RUN_FULL_BENCHMARK=1` + fixture 存在时测百万行）。
final class AdsImportPerformanceTests: XCTestCase {
    func testAdsImportAndETLWithinReasonableTime() async throws {
        let rowCount = BenchmarkConfiguration.performanceAdsRowTarget()
        let merchantRows = min(max(rowCount / 20, 100), BenchmarkConfiguration.fullBenchmarkMerchantRowCount)

        if rowCount >= BenchmarkConfiguration.fullBenchmarkAdsRowCount,
           FileManager.default.fileExists(atPath: BenchmarkConfiguration.adsFixtureURL.path) {
            try await runFullFixtureImportBenchmark()
            return
        }

        let adsURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "perf_ads.csv",
            contents: BenchmarkTestSupport.makeAdsCSV(rowCount: rowCount)
        )
        let merchantURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "perf_merchant.tsv",
            contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: merchantRows)
        )
        defer {
            try? FileManager.default.removeItem(at: adsURL)
            try? FileManager.default.removeItem(at: adsURL)
            try? FileManager.default.removeItem(at: merchantURL)
        }

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        _ = try await MerchantCenterImporter(databaseClient: databaseClient)
            .importFile(sourceURL: merchantURL) { _ in }

        let start = CFAbsoluteTimeGetCurrent()
        let adsResult = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let adsCount = try await databaseClient.countAdsProductDaily(importId: adsResult.importId)
        XCTAssertGreaterThanOrEqual(adsCount, rowCount - 10)
        XCTAssertLessThan(elapsed, 120, "Ads \(rowCount) 行导入 + ETL 应在 120s 内，实测 \(elapsed)s")
    }

    func testAdsImportMeasureBlock() async throws {
        let rowCount = 1_000
        let adsURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "measure_ads.csv",
            contents: BenchmarkTestSupport.makeAdsCSV(rowCount: rowCount)
        )
        let merchantURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "measure_merchant.tsv",
            contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: 50)
        )
        defer {
            try? FileManager.default.removeItem(at: adsURL)
            try? FileManager.default.removeItem(at: merchantURL)
        }

        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            group.enter()
            Task {
                do {
                    let client = try DatabaseClient.makeInMemoryForTesting()
                    _ = try await MerchantCenterImporter(databaseClient: client)
                        .importFile(sourceURL: merchantURL) { _ in }
                    _ = try await AdsProductImporter(databaseClient: client)
                        .importFile(sourceURL: adsURL) { _ in }
                    try await client.rebuildProductWeeklyMetrics()
                } catch {
                    XCTFail("\(error)")
                }
                group.leave()
            }
            group.wait()
        }
    }

    private func runFullFixtureImportBenchmark() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = BenchmarkConfiguration.merchantFixtureURL
        let adsURL = BenchmarkConfiguration.adsFixtureURL

        if FileManager.default.fileExists(atPath: merchantURL.path) {
            _ = try await MerchantCenterImporter(databaseClient: databaseClient)
                .importFile(sourceURL: merchantURL) { _ in }
        }

        let start = CFAbsoluteTimeGetCurrent()
        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 3600, "百万行基准应在 1 小时内完成，实测 \(elapsed)s")
    }
}
