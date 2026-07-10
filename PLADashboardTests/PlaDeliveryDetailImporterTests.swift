import XCTest
@testable import PLADashboard

final class PlaDeliveryDetailImporterTests: XCTestCase {
    private let sampleCSV = """
日期,LSIN,Market Cost,Impressions,Clicks,Conversions,Conversion Value
2026-05-24,S9730219,282.68,25401.0,380.0,6.94,314.16
2026-05-24,S19954192,127.99,11342.0,165.0,5.63,147.42
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
}
