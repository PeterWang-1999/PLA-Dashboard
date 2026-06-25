import XCTest
@testable import PLADashboard

/// 使用本机真实自建站 Merchant 导出验证类目导入（仅本地开发路径存在时运行）。
final class RealSelfBuiltMerchantImportTests: XCTestCase {
    private let productionTSVPath =
        "/Users/litb/Downloads/临时_未分类/商品_2026-06-24_19-15-50.tsv"

    func testProductionSelfBuiltMerchantPopulatesCategoryCatalog() async throws {
        guard ProcessInfo.processInfo.environment["PLA_RUN_REAL_MERCHANT_IMPORT"] == "1" else {
            throw XCTSkip("设置 PLA_RUN_REAL_MERCHANT_IMPORT=1 以运行大文件导入测试")
        }
        guard FileManager.default.fileExists(atPath: productionTSVPath) else {
            throw XCTSkip("本机样例 TSV 不存在")
        }

        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let importer = MerchantCenterImporter(databaseClient: databaseClient, accountKind: .selfBuilt)
        let result = try await importer.importFile(
            sourceURL: URL(fileURLWithPath: productionTSVPath)
        ) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertGreaterThan(result.job.validRows, 1000)

        let categoryCount = try await databaseClient.countProductsWithCategory()
        XCTAssertGreaterThan(categoryCount, 1000, "products.google_product_category 应有大量非空值")

        let snapshot = try await databaseClient.buildFilterCatalogSnapshot()
        XCTAssertFalse(
            snapshot.categoryCatalog.groups.isEmpty,
            "类目 catalog 不应为空；groups=\(snapshot.categoryCatalog.groups.map(\.level2))"
        )
        XCTAssertTrue(
            snapshot.categoryCatalog.groups.contains { $0.level2 == "Men's Shoes" }
                || snapshot.categoryCatalog.groups.contains { $0.level2 == "Shoes" },
            "应包含 Men's Shoes 或 Shoes 二级类目"
        )
    }
}
