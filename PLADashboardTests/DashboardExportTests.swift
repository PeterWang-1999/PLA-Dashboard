import XCTest
@testable import PLADashboard

final class DashboardExportTests: XCTestCase {
    func testExportCSVIncludesBOMHeaderAndFilterMetadata() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = try writeTemporaryFile(
            name: "export_merchant.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "export_ads.csv",
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

        let bundle = try await databaseClient.fetchDashboardAllRows(filters: DashboardQueryFilters())
        XCTAssertEqual(bundle.totalCount, 1)

        let document = DashboardExportCSVDocument(
            bundle: bundle,
            filters: DashboardQueryFilters(searchText: "104166"),
            includeClicksAndConversions: true
        )
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: document.text.utf8)
        XCTAssertEqual(data.prefix(3), Data([0xEF, 0xBB, 0xBF]))

        let csv = String(data: data, encoding: .utf8)!
        XCTAssertTrue(csv.contains("# search=\"104166\""))
        XCTAssertTrue(csv.contains("产品 ID"))
        XCTAssertTrue(csv.contains("点击次数"))
        XCTAssertTrue(csv.contains("10416614474003"))
    }

    func testExportRejectsTooManyRows() {
        let error = DashboardExportError.tooManyRows(60_000, limit: 50_000)
        XCTAssertTrue(error.localizedDescription.contains("60,000") || error.localizedDescription.contains("60000"))
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
