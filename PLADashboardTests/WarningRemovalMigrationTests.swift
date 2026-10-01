import XCTest
@testable import PLADashboard

final class WarningRemovalMigrationTests: XCTestCase {
    func testUpgradeFromV9RemovesWarningStorageAndPreservesCoreData() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting(migrationTarget: "v9_missing_in_gmc")
        _ = try await client.explainQueryPlan(sql: "SELECT warning_label FROM product_weekly_metrics")
        _ = try await client.explainQueryPlan(sql: "SELECT * FROM label_snapshots")
        _ = try await client.explainQueryPlan(sql: "SELECT * FROM label_snapshot_products")
        let merchant = try BenchmarkTestSupport.writeTemporaryFile(
            name: "migration_merchant.tsv", contents: BenchmarkTestSupport.makeMerchantTSV(rowCount: 2)
        )
        let ads = try BenchmarkTestSupport.writeTemporaryFile(
            name: "migration_ads.csv", contents: BenchmarkTestSupport.makeAdsCSV(rowCount: 40)
        )
        defer {
            try? FileManager.default.removeItem(at: merchant)
            try? FileManager.default.removeItem(at: ads)
        }
        _ = try await MerchantCenterImporter(databaseClient: client).importFile(sourceURL: merchant) { _ in }
        _ = try await AdsProductImporter(databaseClient: client).importFile(sourceURL: ads) { _ in }
        try await client.rebuildProductWeeklyMetrics()
        let before = try await client.fetchDashboardAllRows(filters: DashboardQueryFilters())
        let jobs = try await client.fetchImportJobs()
        XCTAssertEqual(before.totalCount, 2)
        try await client.migrateIfNeeded()
        try await client.migrateIfNeeded() // 重复初始化仍为幂等。
        let after = try await client.fetchDashboardAllRows(filters: DashboardQueryFilters())
        let migratedJobs = try await client.fetchImportJobs()
        XCTAssertEqual(after.rows, before.rows)
        XCTAssertEqual(after.weekStarts, before.weekStarts)
        XCTAssertEqual(migratedJobs.map(\.id), jobs.map(\.id))
        for sql in [
            "SELECT warning_label FROM product_weekly_metrics",
            "SELECT * FROM label_snapshots",
            "SELECT * FROM label_snapshot_products"
        ] {
            do {
                _ = try await client.explainQueryPlan(sql: sql)
                XCTFail("Retired storage should be absent: \(sql)")
            } catch { /* SQLite 拒绝已移除的表或列。 */ }
        }
        try await client.rebuildProductWeeklyMetrics()
        let rebuilt = try await client.fetchDashboardAllRows(filters: DashboardQueryFilters())
        XCTAssertEqual(rebuilt.rows, before.rows)
    }

    func testExportsKeepCoreColumnsAndCustomLabelsWithoutWarnings() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 40, merchantRows: 2)
        let filters = DashboardQueryFilters(customLabelFilter: .value(column: "自定义标签 0", value: "EN"))
        let bundle = try await client.fetchDashboardAllRows(filters: filters)
        XCTAssertEqual(bundle.totalCount, 2)
        let document = DashboardExportCSVDocument(bundle: bundle, filters: filters, includeClicksAndConversions: true)
        XCTAssertFalse(document.text.contains("预警"))
        XCTAssertFalse(document.text.contains("alert_filter"))
        XCTAssertTrue(document.text.contains("# custom_label_filter=\"EN\""))
        XCTAssertTrue(document.text.contains("ROI"))
        XCTAssertTrue(document.text.contains("点击次数"))
        XCTAssertFalse(DashboardColumn.allCases.map(\.rawValue).contains("预警标签"))
    }
}
