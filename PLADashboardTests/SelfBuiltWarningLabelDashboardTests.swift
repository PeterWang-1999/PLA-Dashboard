import XCTest
@testable import PLADashboard

final class SelfBuiltWarningLabelDashboardTests: XCTestCase {
    private let weekStarts = [
        "2026-05-24", "2026-05-31", "2026-06-07",
        "2026-06-14", "2026-06-21", "2026-06-28",
    ]

    func testDashboardShowsObservationLabelFromSnapshot() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedAds(client: client)

        let outcome = try await client.recomputeWarningLabelsIfNeeded(force: true)
        guard case .computed = outcome else {
            return XCTFail("Expected computed labels, got \(outcome)")
        }

        let page = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(warningLabelEngine: .selfBuiltSnapshot),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(page.rows.count, 1)
        XCTAssertEqual(page.rows[0].warningLabel, LabelEngineConstants.labelObservation)
        XCTAssertEqual(page.rows[0].warningStyle, .observation)
    }

    func testDashboardShowsDashWhenNoSnapshot() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedAds(client: client)

        let page = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(warningLabelEngine: .selfBuiltSnapshot),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(page.rows.count, 1)
        XCTAssertEqual(page.rows[0].warningLabel, "—")
        XCTAssertEqual(page.rows[0].warningStyle, .none)
    }

    func testAlertFilterObservation() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedAds(client: client)
        _ = try await client.recomputeWarningLabelsIfNeeded(force: true)

        let filtered = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(
                alertFilter: ProductWarningLabel.observation.rawValue,
                warningLabelEngine: .selfBuiltSnapshot
            ),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(filtered.rows.count, 1)

        let highOnly = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(
                alertFilter: ProductWarningLabel.highEfficiency.rawValue,
                warningLabelEngine: .selfBuiltSnapshot
            ),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(highOnly.rows.count, 0)
    }

    private func seedAds(client: DatabaseClient) async throws {
        let merchantURL = try writeTemp(
            name: "m.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Item\tS2001\thttps://example.com\thttps://example.com/a.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        var ads = [
            "Ador - 产品数据",
            "2026-05-24 - 2026-07-04",
            "天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值",
        ]
        for week in weekStarts {
            ads.append("\(week)\tS2001\tC\tUSD\t1.00\t10\t1\t0.0\t$0.50")
        }
        ads.append("2026-07-04\tS2001\tC\tUSD\t1.00\t10\t1\t0.0\t$0.50")
        let adsURL = try writeTemp(name: "a.csv", contents: ads.joined(separator: "\n") + "\n")
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }
        _ = try await MerchantCenterImporter(databaseClient: client)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
        try await client.rebuildProductWeeklyMetrics()
    }

    private func writeTemp(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
