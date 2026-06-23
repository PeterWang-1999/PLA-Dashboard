import XCTest
@testable import PLADashboard

final class WeeklyMetricsAggregatorTests: XCTestCase {
    func testRebuildCreatesWeeklyMetricsFromAdsOnly() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()

        let merchantURL = try writeTemporaryFile(
            name: "merchant.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
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
        let count = try await databaseClient.productWeeklyMetricsCount()
        XCTAssertGreaterThan(count, 0)

        let weekStart = try XCTUnwrap(WeekCalendar.weekStartSunday(forDay: "2026-06-20"))
        let metrics = try await databaseClient.fetchWeeklyMetrics(
            productIds: ["10416614474003"],
            weekStarts: [weekStart]
        )
        XCTAssertEqual(metrics.count, 1)
        XCTAssertGreaterThan(metrics[0].costCents, 0)
        XCTAssertGreaterThan(metrics[0].conversionValueCents, 0)
        XCTAssertEqual(metrics[0].grossSalesCents, 0)
    }

    func testSalesTrendDashboardUsesConversionValue() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()

        let merchantURL = try writeTemporaryFile(
            name: "merchant.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
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

        let result = try await databaseClient.fetchDashboardPage(
            filters: DashboardQueryFilters(),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertTrue(result.rows[0].gsTrendWeeks.contains { $0 > 0 })
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
