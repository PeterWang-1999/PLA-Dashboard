import XCTest
@testable import PLADashboard

final class LsinProductIDReconciliationTests: XCTestCase {
    func testMigrationMergesPrefixedMerchantProductIntoNumericAdsProduct() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importedAt = ISO8601DateFormatter().string(from: Date())

        try await databaseClient.upsertProductsBatch(
            [
                ProductRecord(
                    productId: "9730219",
                    title: nil,
                    canonicalLink: nil,
                    imageUrl: nil,
                    customLabel0: nil,
                    customLabel1: nil,
                    customLabel2: nil,
                    customLabel3: nil,
                    customLabel4: nil,
                    lsin: "S9730219",
                    googleProductCategory: nil,
                    firstListedAt: nil,
                    firstSeenAt: importedAt,
                    lastSeenAt: importedAt,
                    updatedFromImportId: "ads"
                ),
            ],
            importId: "ads",
            importedAt: importedAt
        )

        try await databaseClient.upsertProductsBatch(
            [
                ProductRecord(
                    productId: "S9730219",
                    title: "Sample Sandals",
                    canonicalLink: "https://example.com/sandals",
                    imageUrl: "litb-cgis.rightinthebox.com/images/sandals.jpg",
                    customLabel0: nil,
                    customLabel1: nil,
                    customLabel2: nil,
                    customLabel3: nil,
                    customLabel4: nil,
                    lsin: nil,
                    googleProductCategory: nil,
                    firstListedAt: nil,
                    firstSeenAt: importedAt,
                    lastSeenAt: importedAt,
                    updatedFromImportId: "merchant"
                ),
            ],
            importId: "merchant",
            importedAt: importedAt
        )

        try await databaseClient.reconcileLsinPrefixedProductIDs()

        let products = try await databaseClient.fetchProducts(ids: ["9730219", "S9730219"])
        XCTAssertEqual(products.count, 1)
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.productId, "9730219")
        XCTAssertEqual(product.title, "Sample Sandals")
        XCTAssertEqual(product.imageUrl, "litb-cgis.rightinthebox.com/images/sandals.jpg")
        XCTAssertEqual(product.lsin, "S9730219")
    }

    func testDiagnosticsDetectsVisibleProductsWithoutImage() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importedAt = ISO8601DateFormatter().string(from: Date())

        try await databaseClient.upsertProductsBatch(
            [
                ProductRecord(
                    productId: "9730219",
                    title: nil,
                    canonicalLink: nil,
                    imageUrl: nil,
                    customLabel0: nil,
                    customLabel1: nil,
                    customLabel2: nil,
                    customLabel3: nil,
                    customLabel4: nil,
                    lsin: nil,
                    googleProductCategory: nil,
                    firstListedAt: nil,
                    firstSeenAt: importedAt,
                    lastSeenAt: importedAt,
                    updatedFromImportId: "seed"
                ),
            ],
            importId: "seed",
            importedAt: importedAt
        )

        let adsURL = try writeTemporaryFile(
            name: "diag_ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\t9730219\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
            """
        )
        defer { try? FileManager.default.removeItem(at: adsURL) }

        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()

        let report = try await databaseClient.buildProductImageDiagnosticsReport(accountName: "SHO")
        XCTAssertGreaterThanOrEqual(report.dashboardVisibleWithoutImage, 1)
        XCTAssertFalse(report.missingImageSamples.isEmpty)
        XCTAssertTrue(report.formattedText.contains("看板可见但无图"))
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
