import XCTest
@testable import PLADashboard

final class WeeklyMetricsAccuracyTests: XCTestCase {
    func testWeeklyMetricsMatchManualSumForSingleProduct() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "weekly_merchant.tsv",
            contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: 1)
        )
        let adsURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "weekly_ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-15\t00000001_00001_US_en\tCampaign A\tUSD\t10.00\t100\t10\t1.0\t$50.00
            2026-06-16\t00000001_00001_US_en\tCampaign A\tUSD\t5.00\t50\t5\t0.5\t$25.00
            """
        )
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }

        _ = try await MerchantCenterImporter(databaseClient: databaseClient)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()

        let weekStart = try XCTUnwrap(WeekCalendar.weekStartSunday(forDay: "2026-06-15"))
        let metrics = try await databaseClient.fetchWeeklyMetrics(
            productIds: ["00000001"],
            weekStarts: [weekStart]
        )
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics[0].costCents, 1500)
        XCTAssertEqual(metrics[0].conversionValueCents, 7500)
        XCTAssertEqual(metrics[0].clicks, 15)
        XCTAssertEqual(metrics[0].impressions, 150)
    }
}
