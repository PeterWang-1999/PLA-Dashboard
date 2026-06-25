import SwiftUI
import XCTest
@testable import PLADashboard

final class DashboardFilterTests: XCTestCase {
    func testCustomLabelDisplayNameMapsToSQLColumn() {
        XCTAssertEqual(
            CustomLabelFilterSelection.value(column: "自定义标签 0", value: "EN").sqlColumnName,
            "custom_label_0"
        )
        XCTAssertEqual(
            CustomLabelFilterSelection.column("自定义标签 2").sqlClause,
            .columnNotEmpty(column: "custom_label_2")
        )
    }

    func testCategoryLevel2SQLMatchIncludesRootPrefix() {
        let match = CategoryFilterSelection.level2("Clothing").sqlMatch
        XCTAssertEqual(match?.exactSuffixPattern, "% > Clothing")
        XCTAssertEqual(match?.nestedSuffixPattern, "% > Clothing > %")
    }

    func testCategoryLevel3SQLMatchIncludesRootPrefix() {
        let match = CategoryFilterSelection.level3(level2: "Clothing", level3: "Dresses").sqlMatch
        XCTAssertEqual(match?.exactSuffixPattern, "% > Clothing > Dresses")
        XCTAssertEqual(match?.nestedSuffixPattern, "% > Clothing > Dresses > %")
    }

    func testDashboardFiltersByCustomLabelAndCategory() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()

        let merchantURL = try writeTemporaryFile(
            name: "merchant.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            Shirt\t15091206_00002_US_en\thttps://example.com/shirt\thttps://example.com/shirt.jpg\tShopify产品\t\t\t\t\tApparel & Accessories > Clothing > Shirts & Tops
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
            2026-06-20\t15091206_00002_US_en\tCampaign B\tUSD\t8.00\t800\t40\t1.0\t$40.00
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

        let labelFilter = DashboardQueryFilters(
            customLabelFilter: .value(column: "自定义标签 0", value: "EN")
        )
        let labelResult = try await databaseClient.fetchDashboardPage(
            filters: labelFilter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(labelResult.totalCount, 1)
        XCTAssertEqual(labelResult.rows.first?.id, "10416614474003")

        let columnFilter = DashboardQueryFilters(
            customLabelFilter: .column("自定义标签 0")
        )
        let columnResult = try await databaseClient.fetchDashboardPage(
            filters: columnFilter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(columnResult.totalCount, 2)

        let categoryFilter = DashboardQueryFilters(
            categoryFilter: .level3(level2: "Clothing", level3: "Dresses")
        )
        let categoryResult = try await databaseClient.fetchDashboardPage(
            filters: categoryFilter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(categoryResult.totalCount, 1)
        XCTAssertEqual(categoryResult.rows.first?.id, "10416614474003")

        let level2Filter = DashboardQueryFilters(
            categoryFilter: .level2("Clothing")
        )
        let level2Result = try await databaseClient.fetchDashboardPage(
            filters: level2Filter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(level2Result.totalCount, 2)
    }

    func testSelfBuiltCategoryFilterUsesNormalizedDisplayPath() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()

        let merchantURL = try writeTemporaryFile(
            name: "merchant-self-built.tsv",
            contents: """
            标题\t序号\t链接\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\t类型
            Sandals\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/sandals\thttps://example.com/sandals.jpg\tEN\t\t\t\t\tShoes & Bags c3349_ > Men's Shoes c16445_ > Men's Sandals c37219_ > Outdoor Sandals c123985_
            Shoes\t15091206_00002_US_en\thttps://example.com/shoes\thttps://example.com/shoes.jpg\tShopify产品\t\t\t\t\tShoes & Bags c3349_ > Men's Shoes c16445_
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
            2026-06-20\t15091206_00002_US_en\tCampaign B\tUSD\t8.00\t800\t40\t1.0\t$40.00
            """
        )

        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }

        _ = try await MerchantCenterImporter(databaseClient: databaseClient, accountKind: .selfBuilt)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()

        let level3Filter = DashboardQueryFilters(
            categoryFilter: .level3(level2: "Men's Shoes", level3: "Men's Sandals")
        )
        let level3Result = try await databaseClient.fetchDashboardPage(
            filters: level3Filter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(level3Result.totalCount, 1)
        XCTAssertEqual(level3Result.rows.first?.id, "10416614474003")

        let level2Filter = DashboardQueryFilters(
            categoryFilter: .level2("Men's Shoes")
        )
        let level2Result = try await databaseClient.fetchDashboardPage(
            filters: level2Filter,
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(level2Result.totalCount, 2)
    }

    func testFormatCurrencyFromCentsAlwaysUsesTwoDecimalPlaces() {
        XCTAssertEqual(DashboardMetricFormatter.formatCurrencyFromCents(316_900), "3,169.00")
        XCTAssertEqual(DashboardMetricFormatter.formatCurrencyFromCents(84_200), "842.00")
        XCTAssertEqual(DashboardMetricFormatter.formatCurrencyFromCents(326_917), "3,269.17")
    }

    func testColumnHeaderSortMapsToDashboardTableSort() {
        let costDescending = [KeyPathComparator(\ProductPerformanceRowModel.sortCostCents, order: .reverse)]
        XCTAssertEqual(DashboardTableSort.from(columnSortOrder: costDescending), .costDescending)

        let roiAscending = [KeyPathComparator(\ProductPerformanceRowModel.sortROI, order: .forward)]
        XCTAssertEqual(DashboardTableSort.from(columnSortOrder: roiAscending), .roiAscending)

        let unsupported = [KeyPathComparator(\ProductPerformanceRowModel.sortLSIN, order: .forward)]
        XCTAssertNil(DashboardTableSort.from(columnSortOrder: unsupported))

        XCTAssertEqual(
            DashboardTableSort.costAscending.columnSortOrder,
            [KeyPathComparator(\ProductPerformanceRowModel.sortCostCents, order: .forward)]
        )
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
