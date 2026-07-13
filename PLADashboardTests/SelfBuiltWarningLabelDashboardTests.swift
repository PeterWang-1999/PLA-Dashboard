import XCTest
import GRDB
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

    /// 自建站按标签筛选应 SQL 真分页：第 2 页只返回剩余行，且 totalPages 正确。
    func testSelfBuiltAlertFilterUsesTruePagination() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let weekStarts = self.weekStarts
        let weekId = weekStarts.last!
        let importId = "seed-import"
        let importedAt = ISO8601DateFormatter().string(from: Date())

        try await client.dbQueue.write { db in
            try ImportJobRecord(
                id: importId,
                sourceKind: ImportSourceKind.plaDeliveryDetail.rawValue,
                fileName: "seed.csv",
                filePathBookmark: Data(),
                fileChecksum: "seed",
                importedAt: importedAt,
                status: ImportJobStatus.succeeded.rawValue,
                totalRows: 5,
                validRows: 5,
                invalidRows: 0,
                warningRows: 0,
                schemaVersion: DatabaseClient.currentImportSchemaVersion
            ).insert(db)

            for index in 1...5 {
                let productId = "P\(index)"
                try ProductRecord(
                    productId: productId,
                    title: "Item \(index)",
                    canonicalLink: nil,
                    imageUrl: nil,
                    customLabel0: nil,
                    customLabel1: nil,
                    customLabel2: nil,
                    customLabel3: nil,
                    customLabel4: nil,
                    lsin: "S\(productId)",
                    googleProductCategory: "Apparel & Accessories > Clothing > Dresses",
                    firstListedAt: "2025-01-01",
                    firstSeenAt: importedAt,
                    lastSeenAt: importedAt,
                    updatedFromImportId: importId
                ).insert(db)

                for week in weekStarts {
                    try ProductWeeklyMetricsRecord.make(
                        productId: productId,
                        weekStart: week,
                        metrics: AggregatedMetrics(
                            costCents: 1_000 * index,
                            impressions: 100,
                            clicks: 10,
                            conversions: 1,
                            conversionValueCents: 1_200,
                            grossSalesCents: 2_000,
                            grossProfitCents: 800
                        )
                    ).insert(db)
                }

                // 锚定报告周：最新投放日取完整周周六 2026-07-04
                try AdsProductDailyRecord(
                    date: "2026-07-04",
                    itemId: "item-\(productId)",
                    productId: productId,
                    variantId: nil,
                    campaign: "C",
                    currencyCode: "USD",
                    costMicros: 1_000_000,
                    impressions: 10,
                    clicks: 1,
                    conversions: 0,
                    conversionValueCents: 50,
                    importId: importId
                ).insert(db)
            }

            try LabelSnapshotRecord(
                weekId: weekId,
                createdAt: importedAt,
                adsWeeksJSON: #"["\#(weekStarts.joined(separator: "\",\""))"]"#,
                historyNote: "test"
            ).insert(db)

            for index in 1...5 {
                try LabelSnapshotProductRecord(
                    weekId: weekId,
                    productId: "P\(index)",
                    label: LabelEngineConstants.labelHigh,
                    failHighRetain: false,
                    marginLt1: false,
                    noSignalRecent3: false,
                    noConvGSCurrentWeek: false,
                    roiGe1x: true,
                    marginGe1: true,
                    weeksInLowSampleOld: 0,
                    weeksInPotentialNew: 0,
                    transitionAction: nil,
                    reason: nil
                ).insert(db)
            }
        }

        let filters = DashboardQueryFilters(
            alertFilter: ProductWarningLabel.highEfficiency.rawValue,
            warningLabelEngine: .selfBuiltSnapshot
        )
        let page1 = try await client.fetchDashboardPage(filters: filters, page: 1, pageSize: 2)
        XCTAssertEqual(page1.totalPages, 3)
        XCTAssertEqual(page1.rows.count, 2)
        XCTAssertTrue(page1.rows.allSatisfy { $0.warningLabel == LabelEngineConstants.labelHigh })

        let page2 = try await client.fetchDashboardPage(filters: filters, page: 2, pageSize: 2)
        XCTAssertEqual(page2.rows.count, 2)
        XCTAssertEqual(page2.totalPages, 3)

        let page3 = try await client.fetchDashboardPage(filters: filters, page: 3, pageSize: 2)
        XCTAssertEqual(page3.rows.count, 1)
        XCTAssertEqual(page3.totalPages, 3)

        let observation = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(
                alertFilter: ProductWarningLabel.observation.rawValue,
                warningLabelEngine: .selfBuiltSnapshot
            ),
            page: 1,
            pageSize: 30
        )
        XCTAssertEqual(observation.rows.count, 0)
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
