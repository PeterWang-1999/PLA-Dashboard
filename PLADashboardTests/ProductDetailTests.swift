import XCTest
@testable import PLADashboard

final class ProductDetailTests: XCTestCase {
    func testFetchProductDetailAggregatesRawShopifySKUsWithinDashboardPeriod() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = try writeTemporaryFile(
            name: "product-detail-merchant.tsv",
            contents: """
            序号\t标题\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4
            shopify_zz_10377544827155_54386967609619\tSample shoe\thttps://example.com/products/10377544827155\thttps://example.com/image.jpg\ten\t采购\t高效产品\torange\titems
            shopify_zz_10377544827155_54386967609620\tSample shoe\thttps://example.com/products/10377544827155\thttps://example.com/image.jpg\ten\t采购\t高效产品\torange\titems
            """
        )
        let adsURL = try writeTemporaryFile(
            name: "product-detail-ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-20
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-10\tshopify_zz_10377544827155_54386967609619\tCampaign A\tUSD\t99.00\t900\t90\t9.0\t900.00
            2026-06-15\tshopify_zz_10377544827155_54386967609619\tCampaign A\tUSD\t10.00\t100\t10\t1.0\t50.00
            2026-06-16\tshopify_zz_10377544827155_54386967609619\tCampaign A\tUSD\t5.00\t50\t5\t0.5\t25.00
            2026-06-17\tshopify_zz_10377544827155_54386967609620\tCampaign A\tUSD\t2.00\t20\t2\t0.0\t0.00
            """
        )
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }

        _ = try await MerchantCenterImporter(databaseClient: databaseClient, accountKind: .thirdParty)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }

        let detail = try await databaseClient.fetchProductDetail(
            productID: "10377544827155",
            weekStarts: ["2026-06-14"],
            latestDataDay: "2026-06-20"
        )

        XCTAssertEqual(detail.productID, "10377544827155")
        XCTAssertEqual(detail.title, "Sample shoe")
        XCTAssertEqual(detail.customLabels.compactMap { $0 }, ["en", "采购", "高效产品", "orange", "items"])
        XCTAssertEqual(detail.skuRows.count, 2)

        let leadingSKU = try XCTUnwrap(detail.skuRows.first)
        XCTAssertEqual(leadingSKU.itemID, "shopify_zz_10377544827155_54386967609619")
        XCTAssertEqual(leadingSKU.variantID, "54386967609619")
        XCTAssertEqual(leadingSKU.costMicros, 15_000_000)
        XCTAssertEqual(leadingSKU.clicks, 15)
        XCTAssertEqual(leadingSKU.conversions, 1.5, accuracy: 0.0001)
        XCTAssertEqual(leadingSKU.conversionValueCents, 7_500)
        XCTAssertEqual(leadingSKU.roi ?? 0, 5.0, accuracy: 0.0001)
    }

    @MainActor
    func testSelfBuiltViewModelRejectsProductDetail() async throws {
        let viewModel = DashboardViewModel()
        viewModel.configure(
            databaseClient: try DatabaseClient.makeInMemoryForTesting(),
            accountKind: .selfBuilt
        )

        do {
            _ = try await viewModel.fetchProductDetail(productID: "10377544827155")
            XCTFail("自建站不应开放 SKU 产品明细")
        } catch let error as ProductDetailError {
            XCTAssertEqual(error.localizedDescription, "产品明细目前仅支持三方站账户。")
        }
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
