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

    func testImportUTF16EncodedCSV() async throws {
        let csv = """
Ador - 产品数据
2026年5月10日 - 2026年6月20日
天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
"""
        guard let utf16Body = csv.data(using: .utf16LittleEndian) else {
            XCTFail("UTF-16 LE encoding unavailable")
            return
        }
        var fileData = Data([0xFF, 0xFE])
        fileData.append(utf16Body)

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try fileData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = AdsProductImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.validRows, 1)
        let rowCount = try await databaseClient.countAdsProductDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 1)
    }

    func testImportUTF16EncodedCSVWithHeaderOnFirstLine() async throws {
        let csv = """
天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
2026/8/7\tshopify_zz_10169084772627_54387183878419\tCampaign A\tUSD\t4.28\t59\t1\t0.5\t145.5
2026/8/7\t15297435_00005_us_en\tCampaign B\tUSD\t0.28\t28\t1\t0\t0
"""
        guard let utf16Body = csv.data(using: .utf16LittleEndian) else {
            XCTFail("UTF-16 LE encoding unavailable")
            return
        }
        var fileData = Data([0xFF, 0xFE])
        fileData.append(utf16Body)

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try fileData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = AdsProductImporter(databaseClient: databaseClient)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.totalRows, 2)
        XCTAssertEqual(result.job.validRows, 2)
        let rowCount = try await databaseClient.countAdsProductDaily(importId: result.importId)
        XCTAssertEqual(rowCount, 2)
    }
}
