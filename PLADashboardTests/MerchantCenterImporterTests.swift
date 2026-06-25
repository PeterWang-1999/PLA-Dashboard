import XCTest
@testable import PLADashboard

final class MerchantCenterImporterTests: XCTestCase {
    private let thirdPartyTSV = """
标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
Sample Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
Sample Shirt\t15091206_00002_US_en\thttps://example.com/shirt\thttps://example.com/shirt.jpg\tShopify产品\t\t\t\t\tApparel & Accessories > Clothing > Shirts & Tops
Invalid Row\t\thttps://example.com/missing\thttps://example.com/missing.jpg\t\t\t\t\t\tApparel & Accessories
"""

    private let selfBuiltTSV = """
标题\t序号\t链接\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
Sample Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
Sample Shirt\t15091206_00002_US_en\thttps://example.com/shirt\thttps://example.com/shirt.jpg\tShopify产品\t\t\t\t\tApparel & Accessories > Clothing > Shirts & Tops
Invalid Row\t\thttps://example.com/missing\thttps://example.com/missing.jpg\t\t\t\t\t\tApparel & Accessories
"""

    func testImportThirdPartyTSV() async throws {
        try await assertImportsMerchantSample(
            tsv: thirdPartyTSV,
            accountKind: .thirdParty
        )
    }

    func testImportSelfBuiltTSVWithLinkColumn() async throws {
        try await assertImportsMerchantSample(
            tsv: selfBuiltTSV,
            accountKind: .selfBuilt
        )
    }

    func testSelfBuiltAccountRejectsThirdPartyCanonicalLinkHeader() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = try writeTemporaryTSV(thirdPartyTSV)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: databaseClient, accountKind: .selfBuilt)

        do {
            _ = try await importer.importFile(sourceURL: tempURL) { _ in }
            XCTFail("Expected missing column error")
        } catch let error as MerchantCenterColumnMapError {
            XCTAssertEqual(
                error.errorDescription,
                "TSV 缺少必需列：链接（自建站 导出格式）"
            )
        }
    }

    private func assertImportsMerchantSample(
        tsv: String,
        accountKind: WorkspaceAccountKind
    ) async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = try writeTemporaryTSV(tsv)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: databaseClient, accountKind: accountKind)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        XCTAssertEqual(result.job.status, ImportJobStatus.succeeded.rawValue)
        XCTAssertEqual(result.job.totalRows, 3)
        XCTAssertEqual(result.job.validRows, 2)
        XCTAssertEqual(result.job.invalidRows, 1)

        let productIds = try await databaseClient.fetchDistinctProductIds(importId: result.importId)
        XCTAssertEqual(Set(productIds), Set(["10416614474003", "15091206"]))

        let products = try await databaseClient.fetchProducts(ids: productIds)
        let dress = try XCTUnwrap(products.first { $0.productId == "10416614474003" })
        XCTAssertEqual(dress.googleProductCategory, "Apparel & Accessories > Clothing > Dresses")

        let snapshot = try await databaseClient.buildFilterCatalogSnapshot()
        XCTAssertTrue(snapshot.categoryCatalog.groups.contains { $0.level2 == "Clothing" })
        XCTAssertTrue(snapshot.customLabelCatalog.groups.contains { $0.columnName == "自定义标签 0" })
    }

    private func writeTemporaryTSV(_ contents: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
