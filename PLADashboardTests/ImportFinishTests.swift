import XCTest
@testable import PLADashboard

final class ImportFinishTests: XCTestCase {
    func testMerchantFinishPreservesWeeklyMetricsAndRepairsMissingGMC() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let ads = try await importAds(client)
        try await finish(.adsProduct, ads, client)
        let before = try await client.fetchWeeklyMetrics(productIds: ["00000001"], weekStarts: ["2026-05-31"])
        let orphan = try await client.fetchProducts(ids: ["00000001"])
        XCTAssertEqual(orphan.first?.missingInGmc, true)
        let orphanPage = try await client.fetchDashboardPage(filters: DashboardQueryFilters(), page: 1, pageSize: 30)
        XCTAssertEqual(orphanPage.rows.first?.isMissingInGMC, true)
        let orphanDetail = try await client.fetchProductDetail(productID: "00000001", weekStarts: orphanPage.weekStarts, latestDataDay: "2026-06-01")
        XCTAssertEqual(orphanDetail.isMissingInGMC, true)
        let merchant = try await importMerchant(client)
        let events = FinishEvents()
        try await finish(.merchantCenter, merchant, client, events: events)
        let after = try await client.fetchWeeklyMetrics(productIds: ["00000001"], weekStarts: ["2026-05-31"])
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(try JSONEncoder().encode(before), try JSONEncoder().encode(after))
        let product = try await client.fetchProducts(ids: ["00000001"])
        XCTAssertEqual(product.first?.missingInGmc, false)
        XCTAssertEqual(product.first?.title, "Bench 0")
        let matchedPage = try await client.fetchDashboardPage(filters: DashboardQueryFilters(), page: 1, pageSize: 30)
        XCTAssertEqual(matchedPage.rows.first?.isMissingInGMC, false)
        XCTAssertEqual(matchedPage.rows.first?.cost, orphanPage.rows.first?.cost)
        XCTAssertEqual(matchedPage.rows.first?.roi, orphanPage.rows.first?.roi)
        let matchedDetail = try await client.fetchProductDetail(productID: "00000001", weekStarts: matchedPage.weekStarts, latestDataDay: "2026-06-01")
        XCTAssertEqual(matchedDetail.isMissingInGMC, false)
        let snapshot = await events.snapshot()
        XCTAssertFalse(snapshot.phases.contains(.rebuildingMetrics))
        XCTAssertTrue(snapshot.phases.contains(.completed))
        XCTAssertEqual(snapshot.catalogs, 1)
        XCTAssertEqual(snapshot.refreshes, 1)
    }

    func testMerchantOnlyFinishLeavesEmptyMetricsAndRefreshesCatalog() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let merchant = try await importMerchant(client)
        let events = FinishEvents()
        try await finish(.merchantCenter, merchant, client, events: events)
        let count = try await client.productWeeklyMetricsCount()
        XCTAssertEqual(count, 0)
        let snapshot = await events.snapshot()
        XCTAssertFalse(snapshot.phases.contains(.rebuildingMetrics))
        XCTAssertEqual(snapshot.catalogs, 1)
        XCTAssertEqual(snapshot.refreshes, 1)
    }

    func testSalesFinishStillRebuildsWithAdsIncludingSalesOnlyWeek() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let ads = try await importAds(client)
        try await finish(.adsProduct, ads, client)
        let sales = try await importSales(client)
        let events = FinishEvents()
        try await finish(.salesReport, sales, client, events: events)
        let metrics = try await client.fetchWeeklyMetrics(productIds: ["00000001"], weekStarts: ["2026-06-21"])
        XCTAssertEqual(metrics.first?.grossSalesCents, 8_000)
        XCTAssertEqual(metrics.first?.grossProfitCents, 2_400)
        XCTAssertEqual(metrics.first?.costCents, 0)
        let snapshot = await events.snapshot()
        XCTAssertTrue(snapshot.phases.contains(.rebuildingMetrics))
        XCTAssertEqual(snapshot.catalogs, 0)
        XCTAssertEqual(snapshot.refreshes, 1)
    }

    func testSalesWithoutAdsDoesNotCreateWeeklyMetrics() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let sales = try await importSales(client)
        let events = FinishEvents()
        try await finish(.salesReport, sales, client, events: events)
        let count = try await client.productWeeklyMetricsCount()
        XCTAssertEqual(count, 0)
        let snapshot = await events.snapshot()
        XCTAssertFalse(snapshot.phases.contains(.rebuildingMetrics))
        XCTAssertEqual(snapshot.refreshes, 1)
    }

    private func importAds(_ client: DatabaseClient) async throws -> ImportResult {
        let url = try BenchmarkTestSupport.writeTemporaryFile(name: "ads.csv", contents: BenchmarkTestSupport.makeAdsCSV(rowCount: 1, days: 1))
        defer { try? FileManager.default.removeItem(at: url) }
        return try await AdsProductImporter(databaseClient: client).importFile(sourceURL: url) { _ in }
    }

    private func importMerchant(_ client: DatabaseClient) async throws -> ImportResult {
        let url = try BenchmarkTestSupport.writeTemporaryFile(name: "merchant.tsv", contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: 1))
        defer { try? FileManager.default.removeItem(at: url) }
        return try await MerchantCenterImporter(databaseClient: client).importFile(sourceURL: url) { _ in }
    }

    private func importSales(_ client: DatabaseClient) async throws -> ImportResult {
        let url = try BenchmarkTestSupport.writeTemporaryFile(name: "sales.csv", contents: "日期,LSIN,Gross Sales($),毛利额($)\n2026-06-21,S00000001,$80.00,$24.00")
        defer { try? FileManager.default.removeItem(at: url) }
        return try await SalesReportImporter(databaseClient: client).importFile(sourceURL: url) { _ in }
    }

    private func finish(_ source: ImportSourceKind, _ result: ImportResult, _ client: DatabaseClient, events: FinishEvents = FinishEvents()) async throws {
        try await ImportPipelineRunner.finishImport(sourceKind: source, result: result, databaseClient: client, accountKind: .thirdParty,
            onProgress: { await events.progress($0) }, reloadFilterCatalogs: { await events.catalog() }, refreshDashboard: { await events.refresh() })
    }
}

private actor FinishEvents {
    var phases: [ImportProgress.Phase] = []
    var catalogs = 0
    var refreshes = 0
    func progress(_ progress: ImportProgress) { phases.append(progress.phase) }
    func catalog() { catalogs += 1 }
    func refresh() { refreshes += 1 }
    func snapshot() -> (phases: [ImportProgress.Phase], catalogs: Int, refreshes: Int) { (phases, catalogs, refreshes) }
}
