import XCTest
import GRDB
@testable import PLADashboard

final class DataRetentionTests: XCTestCase {
    func testPurgeDeletesOnlyExpiredAdsDailyRows() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let adsURL = try writeTemporaryFile(
            name: "retention_ads.csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-05-01\t00000001_00001_US_en\tCampaign A\tUSD\t1.00\t10\t1\t0\t0
            2026-06-20\t00000001_00001_US_en\tCampaign A\tUSD\t2.00\t10\t1\t0\t0
            """
        )
        defer { try? FileManager.default.removeItem(at: adsURL) }

        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }

        let before = try await databaseClient.adsDailyRowCount()
        XCTAssertEqual(before, 2)

        let expired = try await databaseClient.countExpiredAdsDailyRows(retentionDays: 30)
        XCTAssertEqual(expired, 1)

        let deleted = try await databaseClient.purgeExpiredAdsDaily(retentionDays: 30)
        XCTAssertEqual(deleted, 1)

        let after = try await databaseClient.adsDailyRowCount()
        XCTAssertEqual(after, 1)
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private extension DatabaseClient {
    func adsDailyRowCount() async throws -> Int {
        try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ads_product_daily;") ?? 0
        }
    }
}
