import XCTest
@testable import PLADashboard

final class SalesReportImporterTests: XCTestCase {
    private let sampleCSV = """
日期,LSIN,Gross Sales($),毛利额($)
2026-06-20,S14429548,$100.00,$30.00
2026-06-21,S14429549,$25.50,$7.65
2026-06-22,Total,$125.50,$37.65
"""

    func testImportSampleCSV() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try sampleCSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = SalesReportImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.sourceKind, ImportSourceKind.salesReport.rawValue)
        XCTAssertEqual(result.job.totalRows, 3)
        XCTAssertEqual(result.job.validRows, 2)
        XCTAssertEqual(result.job.warningRows, 1)

        let rowCount = try await databaseClient.countSalesDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 2)

        let product = try await databaseClient.fetchProducts(ids: ["14429548"]).first
        XCTAssertEqual(product?.lsin, "S14429548")
    }

    func testSyncReplacesChangedSalesAcrossCategoriesAndSkipsUnchangedRows() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let importer = SalesReportImporter(databaseClient: client)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.csv")
        let second = folder.appendingPathComponent("second.csv")
        let header = "日期,LSIN,Gross Sales($),毛利额($)\n"
        try sampleCSV.write(to: first, atomically: true, encoding: .utf8)
        let original = try await importer.importFile(sourceURL: first) { _ in }

        try (header + "2026-06-20,S14429548,101,31").write(to: first, atomically: true, encoding: .utf8)
        try (header + "2026-06-21,S14429549,25.50,7.65\n2026-06-21,S14429550,10,3")
            .write(to: second, atomically: true, encoding: .utf8)

        let updated = try await importer.importFile(sourceURL: first, additionalSyncFiles: [second], incrementalSync: true) { _ in }
        let repeated = try await importer.importFile(sourceURL: first, additionalSyncFiles: [second], incrementalSync: true) { _ in }
        let originalCount = try await client.countSalesDaily(importId: original.importId)
        let updatedCount = try await client.countSalesDaily(importId: updated.importId)
        let repeatedCount = try await client.countSalesDaily(importId: repeated.importId)
        let coverage = try await client.salesGrossProfitCoverage(weekStarts: [])
        XCTAssertEqual(originalCount, 1)
        XCTAssertEqual(updatedCount, 2)
        XCTAssertEqual(repeatedCount, 0)
        XCTAssertEqual(coverage.salesGrossSumCents, 13_650)
        XCTAssertEqual(coverage.salesProfitSumCents, 4_165)
        let addedProduct = try await client.fetchProducts(ids: ["14429550"]).first
        XCTAssertEqual(addedProduct?.lsin, "S14429550")

        try (header + "2026-06-20,S14429548,200,60").write(to: first, atomically: true, encoding: .utf8)
        try (header + "2026-06-21,S14429549,invalid,7.65").write(to: second, atomically: true, encoding: .utf8)
        do {
            _ = try await importer.importFile(sourceURL: first, additionalSyncFiles: [second], incrementalSync: true) { _ in }
            XCTFail("Expected an invalid row to roll back the sales sync")
        } catch ImportPipelineError.invalidSyncData {
            let afterFailure = try await client.salesGrossProfitCoverage(weekStarts: [])
            XCTAssertEqual(afterFailure.salesGrossSumCents, 13_650)
            XCTAssertEqual(afterFailure.salesProfitSumCents, 4_165)
        }
    }

    func testImportRequiresGrossProfitColumn() async throws {
        let csv = """
日期,LSIN,Gross Sales($)
2026-06-20,S14429548,$100.00
"""
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = SalesReportImporter(databaseClient: databaseClient)
        do {
            _ = try await importer.importFile(sourceURL: tempURL) { _ in }
            XCTFail("Expected missing 毛利额($) column to fail")
        } catch let error as SalesColumnMapError {
            guard case .missingColumn(let name) = error else {
                return XCTFail("Unexpected SalesColumnMapError: \(error)")
            }
            XCTAssertEqual(name, "毛利额($)")
        }
    }

    func testImportPreservesUltraLongGrossProfitFraction() async throws {
        let csv = """
日期,LSIN,Gross Sales($),毛利额($)
2026/7/8,S13918614,216.67,104.351501070163032066938202220754409954
"""
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = SalesReportImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }
        XCTAssertEqual(result.job.validRows, 1)

        let coverage = try await databaseClient.salesGrossProfitCoverage(weekStarts: [])
        XCTAssertEqual(coverage.salesRowsWithGP, 1)
        XCTAssertEqual(coverage.salesProfitSumCents, 10_435)
        XCTAssertEqual(coverage.salesGrossSumCents, 21_667)
    }

    func testImportGBKEncodedCSV() async throws {
        let csv = """
日期,LSIN,Gross Sales($),毛利额($)
2026-06-20,S14429548,$100.00,$30.00
2026-06-22,Total,$100.00,$30.00
"""
        guard let gbkData = csv.data(using: ImportTextEncoding.gb18030) else {
            XCTFail("GB18030 encoding unavailable")
            return
        }

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try gbkData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = SalesReportImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.validRows, 1)
        let rowCount = try await databaseClient.countSalesDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 1)
    }
}
