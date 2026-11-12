import XCTest
@testable import PLADashboard

final class PlaDeliveryDetailImporterTests: XCTestCase {
    private let sampleCSV = """
日期,LSIN,Market Cost,Impressions,Clicks,Conversions,Conversion Value,首次上架时间
2026-05-24,S9730219,282.68,25401.0,380.0,6.94,314.16,2026-03-01
2026-05-24,S19954192,127.99,11342.0,165.0,5.63,147.42,2025-01-15
"""

    func testImportCSVWithoutSkippingHeaderLines() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try sampleCSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.sourceKind, ImportSourceKind.plaDeliveryDetail.rawValue)
        XCTAssertEqual(result.job.totalRows, 2)
        XCTAssertEqual(result.job.validRows, 2)

        let rowCount = try await databaseClient.countAdsProductDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 2)

        let rows = try await databaseClient.fetchAdsProductDaily(importId: result.importId)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(first.itemId, "S9730219")
        XCTAssertEqual(first.productId, "9730219")
        XCTAssertEqual(first.campaign, PlaDeliveryDetailColumnMap.placeholderCampaign)
        XCTAssertEqual(first.currencyCode, PlaDeliveryDetailColumnMap.placeholderCurrencyCode)
        XCTAssertEqual(first.impressions, 25401)
        XCTAssertEqual(first.clicks, 380)
        XCTAssertEqual(first.costMicros, 282_680_000)
        XCTAssertEqual(first.conversionValueCents, 31416)

        let product = try await databaseClient.fetchProducts(ids: ["9730219"]).first
        XCTAssertEqual(product?.firstListedAt, "2026-03-01")
    }

    func testImportCSVWithoutFirstListedColumnStillSucceeds() async throws {
        let csv = """
日期,LSIN,Market Cost,Impressions,Clicks,Conversions,Conversion Value
2026-05-24,S9730219,282.68,25401.0,380.0,6.94,314.16
"""
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }
        XCTAssertEqual(result.job.validRows, 1)
        let product = try await databaseClient.fetchProducts(ids: ["9730219"]).first
        XCTAssertNil(product)
    }

    func testImportXLSXFixture() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SamplePlaDeliveryDetail.xlsx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: fixture) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.sourceKind, ImportSourceKind.plaDeliveryDetail.rawValue)
        XCTAssertEqual(result.job.validRows, 1)

        let rows = try await databaseClient.fetchAdsProductDaily(importId: result.importId)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.productId, "9730219")
        XCTAssertEqual(row.impressions, 25401)
        XCTAssertEqual(row.conversionValueCents, 31416)
    }

    func testImportXLSXSharedStringsFixture() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SamplePlaDeliveryDetailSharedStrings.xlsx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: fixture) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.validRows, 1)

        let rows = try await databaseClient.fetchAdsProductDaily(importId: result.importId)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.itemId, "S9730219")
        XCTAssertEqual(row.productId, "9730219")
        XCTAssertEqual(row.date, "2026-05-24")
        XCTAssertEqual(row.impressions, 25401)
        XCTAssertEqual(row.conversionValueCents, 31416)
    }

    func testColumnIndexFromCellReference() {
        XCTAssertEqual(XLSXSheetXMLBridge.columnIndex(fromCellReference: "A1"), 0)
        XCTAssertEqual(XLSXSheetXMLBridge.columnIndex(fromCellReference: "I2"), 8)
        XCTAssertEqual(XLSXSheetXMLBridge.columnIndex(fromCellReference: "AA1"), 26)
    }

    func testIncrementalSyncSkipsIdenticalRowsAndReplacesOnlyChangedKeys() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.csv")
        let second = directory.appendingPathComponent("second.csv")
        try sampleCSV.write(to: first, atomically: true, encoding: .utf8)
        let original = try await importer.importFile(sourceURL: first, incrementalSync: true) { _ in }

        let identical = try await importer.importFile(sourceURL: first, incrementalSync: true) { _ in }
        let identicalCount = try await databaseClient.countAdsProductDaily(importId: identical.importId)
        XCTAssertEqual(identicalCount, 0)

        try sampleCSV.replacingOccurrences(of: "282.68", with: "300.00").write(to: first, atomically: true, encoding: .utf8)
        let header = try XCTUnwrap(sampleCSV.split(separator: "\n").first)
        try "\(header)\n2026-05-24,S9730219,1.00,4,2,1,5,2026-03-01".write(to: second, atomically: true, encoding: .utf8)
        let updated = try await importer.importFile(
            sourceURL: first, additionalSyncFiles: [second], incrementalSync: true
        ) { _ in }
        let updatedRows = try await databaseClient.fetchAdsProductDaily(importId: updated.importId)
        XCTAssertEqual(updatedRows.map(\.costMicros), [301_000_000])
        let retained = try await databaseClient.fetchAdsProductDaily(importId: original.importId)
        XCTAssertEqual(retained.map(\.itemId), ["S19954192"])

        try "bad header".write(to: second, atomically: true, encoding: .utf8)
        do {
            _ = try await importer.importFile(sourceURL: first, additionalSyncFiles: [second], incrementalSync: true) { _ in }
            XCTFail("Malformed second file should fail the batch")
        } catch {
            let afterFailure = try await databaseClient.countAdsProductDaily(importId: updated.importId)
            XCTAssertEqual(afterFailure, 1)
        }
    }

    func testCancellingSyncBeforeCommitPreservesPreviousRows() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let importer = PlaDeliveryDetailImporter(databaseClient: client)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: file) }
        try sampleCSV.write(to: file, atomically: true, encoding: .utf8)
        let previous = try await importer.importFile(sourceURL: file, incrementalSync: true) { _ in }

        try sampleCSV.replacingOccurrences(of: "282.68", with: "300.00").write(to: file, atomically: true, encoding: .utf8)
        let cancelledImport = Task {
            try await importer.importFile(sourceURL: file, incrementalSync: true) { progress in
                if case .finalizing = progress.phase {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }

        do {
            _ = try await cancelledImport.value
            XCTFail("Cancelled sync should not commit")
        } catch ImportPipelineError.cancelled {
            let jobs = try await client.fetchImportJobs()
            let cancelled = try XCTUnwrap(jobs.first { $0.status == ImportJobStatus.cancelled.rawValue })
            let cancelledRows = try await client.countAdsProductDaily(importId: cancelled.id)
            XCTAssertEqual(cancelledRows, 0)
            let previousRows = try await client.fetchAdsProductDaily(importId: previous.importId)
            XCTAssertEqual(previousRows.map(\.costMicros).sorted(), [127_990_000, 282_680_000])
        }
    }

    func testSelfBuiltCategoryFilterUsesFullProductDetailPath() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let csv = """
        日期,LSIN,CMS1,CMS2,CMS3,CMS4,Market Cost,Impressions,Clicks,Conversions,Conversion Value
        2026-05-24,S9730219,Toys & Hobbies,Toys & Games,Games,Accessories,10,100,5,1,20
        2026-05-24,S19954192,Toys & Hobbies,Pet Supplies,Games,Accessories,20,200,10,2,40
        """
        let file = try BenchmarkTestSupport.writeTemporaryFile(name: "pla-category.csv", contents: csv)
        defer { try? FileManager.default.removeItem(at: file) }
        let importer = PlaDeliveryDetailImporter(databaseClient: client)
        _ = try await importer.importFile(sourceURL: file, incrementalSync: true) { _ in }
        try await client.refreshProductWeeklyMetricsAfterImport()

        let catalog = try await client.buildFilterCatalogSnapshot(accountKind: .selfBuilt)
        let root = try XCTUnwrap(catalog.plaCategories.first)
        XCTAssertEqual(root.name, "Toys & Hobbies")
        XCTAssertEqual(root.children.map(\.name), ["Pet Supplies", "Toys & Games"])
        let toys = try XCTUnwrap(root.children.last)
        let accessories = try XCTUnwrap(toys.children.first?.children.first)
        XCTAssertEqual(accessories.name, "Accessories")

        for (path, expected) in [(root.path, ["9730219", "19954192"]), (toys.path, ["9730219"]), (accessories.path, ["9730219"])] {
            let selection = try await client.fetchDataDashboardProductSelection(filters: DashboardQueryFilters(categoryFilter: .plaPath(path)))
            XCTAssertEqual(Set(selection.productIDs), Set(expected))
        }
    }

    func testProductTagFilterUsesLatestReportDayAndCombinesWithCategory() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let importer = PlaDeliveryDetailImporter(databaseClient: client)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: file) }
        let header = "日期,LSIN,CMS1,CMS2,Product Tag,Market Cost,Impressions,Clicks,Conversions,Conversion Value"
        let latest = "2026-05-24,S9730219,Toys & Hobbies,Toys & Games,高效,10,100,5,1,20"
        let older = "2026-05-23,S9730219,Toys & Hobbies,Toys & Games,低效,10,100,5,1,20"
        let pet = "2026-05-24,S19954192,Toys & Hobbies,Pet Supplies,高效,20,200,10,2,40"
        try [header.replacingOccurrences(of: "Product Tag", with: "ProductTag"), latest, older, pet]
            .joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        _ = try await importer.importFile(sourceURL: file, incrementalSync: true) { _ in }
        try await client.refreshProductWeeklyMetricsAfterImport()

        let catalog = try await client.buildFilterCatalogSnapshot(accountKind: .selfBuilt)
        XCTAssertEqual(catalog.productTags, ["高效"])
        let filters = DashboardQueryFilters(categoryFilter: .plaPath("Toys & Hobbies > Toys & Games"), productTag: "高效")
        let page = try await client.fetchDashboardPage(filters: filters, page: 1, pageSize: 30)
        XCTAssertEqual(page.rows.map(\.id), ["9730219"])

        try [header, older].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        _ = try await importer.importFile(sourceURL: file, incrementalSync: true) { _ in }
        let afterOlderImport = try await client.fetchDataDashboardProductSelection(filters: filters)
        XCTAssertEqual(afterOlderImport.productIDs, ["9730219"])

        let untagged = latest.replacingOccurrences(of: ",高效,", with: ",,")
        try [header, untagged].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        _ = try await importer.importFile(sourceURL: file, incrementalSync: true) { _ in }
        let afterTagRemoval = try await client.fetchDataDashboardProductSelection(filters: filters)
        XCTAssertTrue(afterTagRemoval.productIDs.isEmpty)
        let thirdParty = try await client.buildFilterCatalogSnapshot()
        XCTAssertTrue(thirdParty.productTags.isEmpty)
    }
}

final class PurgeLegacyGoogleAdsImportsTests: XCTestCase {
    func testPurgeRemovesAdsProductButKeepsPlaDeliveryDetail() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()

        let adsCSV = """
Ador - 产品数据
2026-06-01 - 2026-06-22
天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
2026-06-20\tS111\tCampaign A\tUSD\t1.00\t10\t1\t1.0\t$10.00
"""
        let adsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try adsCSV.write(to: adsURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: adsURL) }

        let adsResult = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        XCTAssertEqual(adsResult.job.validRows, 1)

        let plaCSV = """
日期,LSIN,Market Cost,Impressions,Clicks,Conversions,Conversion Value
2026-05-24,S222,1.00,10.0,1.0,1.0,10.00
"""
        let plaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try plaCSV.write(to: plaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: plaURL) }

        let plaResult = try await PlaDeliveryDetailImporter(databaseClient: databaseClient)
            .importFile(sourceURL: plaURL) { _ in }
        XCTAssertEqual(plaResult.job.validRows, 1)

        let didDelete = try await databaseClient.purgeLegacyGoogleAdsImports()
        XCTAssertTrue(didDelete)

        let adsCount = try await databaseClient.countAdsProductDaily(importId: adsResult.importId)
        let plaCount = try await databaseClient.countAdsProductDaily(importId: plaResult.importId)
        XCTAssertEqual(adsCount, 0)
        XCTAssertEqual(plaCount, 1)

        let jobs = try await databaseClient.fetchImportJobs()
        XCTAssertFalse(jobs.contains { $0.sourceKind == ImportSourceKind.adsProduct.rawValue })
        XCTAssertTrue(jobs.contains { $0.sourceKind == ImportSourceKind.plaDeliveryDetail.rawValue })
    }

    func testImportCSVStoresPrimaryCMS3BySpend() async throws {
        let csv = """
日期,LSIN,Market Cost,Impressions,Clicks,Conversions,Conversion Value,CMS3
2026-05-24,S9730219,100.00,1000.0,10.0,1.0,50.00,Dresses
2026-05-25,S9730219,300.00,2000.0,20.0,2.0,100.00,Shoes
2026-05-26,S9730219,50.00,500.0,5.0,0.5,20.00,Dresses
"""
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
        _ = try await importer.importFile(sourceURL: tempURL) { _ in }

        let product = try await databaseClient.fetchProducts(ids: ["9730219"]).first
        XCTAssertEqual(product?.plaCms3, "Shoes")
    }
}
