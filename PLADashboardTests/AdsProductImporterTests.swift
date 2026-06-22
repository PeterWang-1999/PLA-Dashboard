import XCTest
@testable import PLADashboard

final class AdsProductImporterTests: XCTestCase {
    private let sampleCSV = """
Ador - 产品数据
2026-06-01 - 2026-06-22
天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
2026-06-21\t15091206_00002_US_en\tCampaign B\tUSD\t5.00\t500\t20\t1.0\t$45.50
"""

    func testImportSampleWithSkippedHeaderLines() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try sampleCSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = AdsProductImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.sourceKind, ImportSourceKind.adsProduct.rawValue)
        XCTAssertEqual(result.job.totalRows, 2)
        XCTAssertEqual(result.job.validRows, 2)

        let rowCount = try await databaseClient.countAdsProductDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 2)
    }
}
