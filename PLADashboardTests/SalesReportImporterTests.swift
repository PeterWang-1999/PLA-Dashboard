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
