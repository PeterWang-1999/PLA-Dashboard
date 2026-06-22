import XCTest
@testable import PLADashboard

final class SalesReportImporterTests: XCTestCase {
    private let sampleCSV = """
日期,LSIN,Gross Sales($)
2026-06-20,S14429548,$100.00
2026-06-21,S14429549,$25.50
2026-06-22,Total,$125.50
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
}
