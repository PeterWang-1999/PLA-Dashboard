import XCTest
@testable import PLADashboard

final class ImportAccuracyTests: XCTestCase {
    func testAdsImportPreservesCostAndConversionValue() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "accuracy_merchant.tsv",
            contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: 1)
        )
        let adsURL = try BenchmarkTestSupport.writeTemporaryFile(
            name: "accuracy_ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-06-20\t00000001_00001_US_en\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
            """
        )
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }

        _ = try await MerchantCenterImporter(databaseClient: databaseClient)
            .importFile(sourceURL: merchantURL) { _ in }
        let adsResult = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }

        let count = try await databaseClient.countAdsProductDaily(importId: adsResult.importId)
        XCTAssertEqual(count, 1)

        let rows = try await databaseClient.fetchAdsProductDaily(importId: adsResult.importId)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].costMicros, 12_340_000)
        XCTAssertEqual(rows[0].conversionValueCents, 9900)
        XCTAssertEqual(rows[0].productId, "00000001")
        XCTAssertEqual(rows[0].date, "2026-06-20")
    }

    func testBenchProductIDNormalizerFormat() {
        let normalized = ProductIDNormalizer.normalize("00000042_00001_US_en")
        XCTAssertEqual(normalized.productID, "00000042")
        XCTAssertEqual(normalized.confidence, .high)
    }
}
