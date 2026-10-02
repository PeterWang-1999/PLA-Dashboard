import XCTest
@testable import PLADashboard

final class IncrementalWeeklyMetricsTests: XCTestCase {
    static let weeks = ["2026-05-31", "2026-06-07", "2026-06-14", "2026-06-21"]

    func testInitialRefreshAndAdsOverwriteMatchFullRebuild() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "first", ads: [ads("A", micros: 10001), ads("B")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "second", ads: [
            ads("A", micros: 25009), ads("A", day: "2026-06-15", item: "sku2", campaign: "other", micros: 15001)
        ])
        try await assertEquivalent(client)
        let rows = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: Self.weeks)
        XCTAssertEqual(rows.first { $0.weekStart == "2026-05-31" }?.costCents, 2)
        XCTAssertEqual(rows.first { $0.weekStart == "2026-06-14" }?.costCents, 1)
    }

    func testSalesOnlyWeeksAndFirstAdsEligibilityArePreserved() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "sales-first", sales: [sales("A"), sales("B", day: "2026-06-21")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "ads", ads: [ads("A"), ads("B")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "sales-update", sales: [sales("B", day: "2026-06-21", gross: 9000)])
        try await assertEquivalent(client)
        let rows = try await client.fetchWeeklyMetrics(productIds: ["B"], weekStarts: Self.weeks)
        let salesWeek = try XCTUnwrap(rows.first { $0.weekStart == "2026-06-21" })
        XCTAssertEqual(salesWeek.costCents, 0)
        XCTAssertEqual(salesWeek.grossSalesCents, 9000)
    }

    func testRemappedNaturalKeyDoesNotResurrectOldProductOnLaterRefresh() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "old", ads: [ads("A", item: "shared"), ads("C")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "remap", ads: [ads("B", item: "shared")])
        try await assertEquivalent(client)
        // 此时仅 A 新失效，仍必须读取 shared 键下 B 的覆盖记录。
        try await client.addWeeklyFixture(id: "later", ads: [ads("A", day: "2026-06-15", item: "new")])
        try await assertEquivalent(client)
        let rows = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: Self.weeks)
        XCTAssertEqual(rows.map(\.weekStart), ["2026-06-14"])
    }

    func testRemappedSalesKeyClearsOldProduct() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "initial", ads: [ads("A"), ads("B")], sales: [sales("A", lsin: "shared")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "remap-sales", sales: [sales("B", lsin: "shared", gross: 9000)])
        try await assertEquivalent(client)
        let rows = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: Self.weeks)
        XCTAssertEqual(rows.first?.grossSalesCents, 0)
    }

    func testPendingSuccessfulImportsSurviveReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("incremental.sqlite")
        let first = try DatabaseClient.make(at: url, accountID: "incremental")
        try await first.addWeeklyFixture(id: "initial", ads: [ads("C")])
        try await first.rebuildProductWeeklyMetrics()
        try await first.addWeeklyFixture(id: "pending-one", ads: [ads("A")])
        try await first.addWeeklyFixture(id: "pending-two", ads: [ads("B")])
        let reopened = try DatabaseClient.make(at: url, accountID: "incremental")
        try await assertEquivalent(reopened)
        let rows = try await reopened.fetchWeeklyMetrics(productIds: ["A", "B", "C"], weekStarts: Self.weeks)
        XCTAssertEqual(rows.count, 3)
    }

    func testRollbackAndCancellationKeepSafeRecoveryPath() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "initial", ads: [ads("A")])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "rolled-back", ads: [ads("B")])
        try await client.rollbackImport(importId: "rolled-back", sourceKind: .adsProduct)
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "pending", ads: [ads("C")])
        let before = try await snapshot(client)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await client.refreshProductWeeklyMetricsAfterImport()
        }
        do { try await task.value; XCTFail("取消任务应抛出 CancellationError") }
        catch is CancellationError { }
        let after = try await snapshot(client)
        XCTAssertEqual(before, after)
        try await assertEquivalent(client)
    }

    func testSameTimestampUsesLatestInsertedRecordConsistently() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "same-one", ads: [ads("A", micros: 10000)])
        try await assertEquivalent(client)
        try await client.addWeeklyFixture(id: "same-two", ads: [ads("A", micros: 20000)])
        try await assertEquivalent(client)
        let rows = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: Self.weeks)
        XCTAssertEqual(rows.first?.costCents, 2)
    }

    func testSameTimestampWeeklyAndDetailMetricsAgree() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 20, merchantRows: 1)
        let url = try BenchmarkTestSupport.writeTemporaryFile(name: "overwrite.csv", contents: BenchmarkTestSupport.makeAdsCSV(rowCount: 20).replacingOccurrences(of: "1.00", with: "51.00"))
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await AdsProductImporter(databaseClient: client).importFile(sourceURL: url) { _ in }
        try await client.refreshProductWeeklyMetricsAfterImport()
        let page = try await client.fetchDashboardPage(filters: DashboardQueryFilters(), page: 1, pageSize: 30)
        let product = try XCTUnwrap(page.rows.first)
        let detail = try await client.fetchProductDetail(productID: product.id, weekStarts: page.weekStarts, latestDataDay: try XCTUnwrap(page.latestDataDay))
        let weekly = try await client.fetchWeeklyMetrics(productIds: [product.id], weekStarts: page.weekStarts)
        XCTAssertEqual(detail.skuRows.reduce(0) { $0 + $1.costMicros } / 10000, weekly.reduce(0) { $0 + $1.costCents })
    }

    func testUpgradeFromV10BuildsSafeBaseline() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting(migrationTarget: "v10_remove_warning_labels")
        try await client.addWeeklyFixture(id: "old-version", ads: [ads("A")])
        try await client.rebuildProductWeeklyMetrics()
        try await client.migrateIfNeeded()
        try await client.addWeeklyFixture(id: "new-version", ads: [ads("B")])
        try await assertEquivalent(client)
    }

    func testCancelledRetentionRebuildIsRecoveredByNextRefresh() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.addWeeklyFixture(id: "retention", ads: [ads("A", day: "2026-05-01")])
        try await client.rebuildProductWeeklyMetrics()
        let before = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: ["2026-04-26"])
        XCTAssertEqual(before.count, 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await client.purgeExpiredAdsDaily(retentionDays: 30)
        }
        do { try await task.value; XCTFail("重建应响应取消") }
        catch is CancellationError { }
        try await client.refreshProductWeeklyMetricsAfterImport()
        let after = try await client.fetchWeeklyMetrics(productIds: ["A"], weekStarts: ["2026-04-26"])
        XCTAssertTrue(after.isEmpty)
    }

    private func assertEquivalent(_ client: DatabaseClient) async throws {
        try await client.refreshProductWeeklyMetricsAfterImport()
        let incremental = try await snapshot(client)
        try await client.rebuildProductWeeklyMetrics()
        let full = try await snapshot(client)
        XCTAssertEqual(incremental, full)
    }

    private func snapshot(_ client: DatabaseClient) async throws -> Data {
        let records = try await client.fetchWeeklyMetrics(productIds: ["A", "B", "C"] + (0..<10).map { "untouched-\($0)" }, weekStarts: Self.weeks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(records.sorted { ($0.productId, $0.weekStart) < ($1.productId, $1.weekStart) })
    }

    private func ads(_ id: String, day: String = "2026-06-01", item: String? = nil, campaign: String = "campaign", micros: Int = 1_000_000) -> AdsProductDailyRecord {
        AdsProductDailyRecord(date: day, itemId: item ?? id, productId: id, variantId: nil,
            campaign: campaign, currencyCode: "USD", costMicros: micros, impressions: 100,
            clicks: 10, conversions: 0.5, conversionValueCents: 200, importId: "")
    }

    private func sales(_ id: String, day: String = "2026-06-01", lsin: String? = nil, gross: Int = 5000) -> SalesDailyRecord {
        SalesDailyRecord(date: day, lsin: lsin ?? id, productId: id, grossSalesCents: gross,
            grossProfitCents: gross / 3, importId: "")
    }
}

private extension DatabaseClient {
    func addWeeklyFixture(id: String, ads: [AdsProductDailyRecord] = [], sales: [SalesDailyRecord] = []) throws {
        // 足够大的未受影响集合，让后续单产品更新实际走增量而非阈值回退。
        let firstAds = try (!ads.isEmpty && !hasFactTableData())
        let background = firstAds ? (0..<10).map { index in
            AdsProductDailyRecord(date: "2026-06-01", itemId: "untouched-\(index)", productId: "untouched-\(index)",
                variantId: nil, campaign: "background", currencyCode: "USD", costMicros: 1_000_000,
                impressions: 100, clicks: 10, conversions: 1, conversionValueCents: 100, importId: "")
        } : []
        let allAds = ads + background
        var job = ImportJobRecord(id: id, sourceKind: ads.isEmpty ? "sales_report" : "ads_product",
            fileName: "fixture", filePathBookmark: nil, fileChecksum: nil,
            importedAt: "2026-07-01T00:00:00Z", status: "running", totalRows: ads.count + sales.count,
            validRows: ads.count + sales.count, invalidRows: 0, warningRows: 0, schemaVersion: 2)
        try createImportJob(job)
        try insertAdsProductDailyBatch(allAds.map { row in var copy = row; copy.importId = id; return copy })
        try insertSalesDailyBatch(sales.map { row in var copy = row; copy.importId = id; return copy })
        job.status = "succeeded"
        try updateImportJob(job)
        if !ads.isEmpty && !sales.isEmpty {
            job.sourceKind = "sales_report"
            try updateImportJob(job)
        }
    }
}
