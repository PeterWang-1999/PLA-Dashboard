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
标题\t序号\t链接\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\t类型
Sample Sandals\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/sandals\thttps://example.com/sandals.jpg\tEN\t\t\t\t\tShoes & Bags c3349_ > Men's Shoes c16445_ > Men's Sandals c37219_ > Outdoor Sandals c123985_
Sample Shoes\t15091206_00002_US_en\thttps://example.com/shoes\thttps://example.com/shoes.jpg\tShopify产品\t\t\t\t\tShoes & Bags c3349_ > Men's Shoes c16445_
Invalid Row\t\thttps://example.com/missing\thttps://example.com/missing.jpg\t\t\t\t\t\tShoes & Bags c3349_
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
        let primaryProduct = try XCTUnwrap(products.first { $0.productId == "10416614474003" })

        switch accountKind {
        case .thirdParty:
            XCTAssertEqual(
                primaryProduct.googleProductCategory,
                "Apparel & Accessories > Clothing > Dresses"
            )
        case .selfBuilt:
            XCTAssertEqual(
                primaryProduct.googleProductCategory,
                "Shoes & Bags > Men's Shoes > Men's Sandals > Outdoor Sandals"
            )
        }

        let snapshot = try await databaseClient.buildFilterCatalogSnapshot()
        switch accountKind {
        case .thirdParty:
            XCTAssertTrue(snapshot.categoryCatalog.groups.contains { $0.level2 == "Clothing" })
        case .selfBuilt:
            XCTAssertTrue(snapshot.categoryCatalog.groups.contains { $0.level2 == "Men's Shoes" })
            XCTAssertTrue(
                snapshot.categoryCatalog.groups
                    .first(where: { $0.level2 == "Men's Shoes" })?
                    .level3.contains("Men's Sandals") == true
            )
        }
        XCTAssertTrue(snapshot.customLabelCatalog.groups.contains { $0.columnName == "自定义标签 0" })
    }

    func testDuplicateMerchantImportRefreshesCategories() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tsv = """
标题\t序号\t链接\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\t类型
Sample\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/p\thttps://example.com/i.jpg\tEN\t\t\t\t\tShoes & Bags c3349_ > Men's Shoes c16445_ > Men's Sandals c37219_
"""
        let url = try writeTemporaryTSV(tsv)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = MerchantCenterImporter(databaseClient: databaseClient, accountKind: .selfBuilt)
        _ = try await importer.importFile(sourceURL: url) { _ in }

        var products = try await databaseClient.fetchProducts(ids: ["10416614474003"])
        XCTAssertEqual(
            products.first?.googleProductCategory,
            "Shoes & Bags > Men's Shoes > Men's Sandals"
        )

        do {
            _ = try await importer.importFile(sourceURL: url) { _ in }
            XCTFail("Expected duplicate import error")
        } catch let error as ImportPipelineError {
            guard case .duplicateFile = error else {
                throw error
            }
        }

        let refreshed = try await importer.refreshProductCategories(sourceURL: url)
        XCTAssertGreaterThan(refreshed, 0)

        products = try await databaseClient.fetchProducts(ids: ["10416614474003"])
        XCTAssertEqual(
            products.first?.googleProductCategory,
            "Shoes & Bags > Men's Shoes > Men's Sandals"
        )

        let snapshot = try await databaseClient.buildFilterCatalogSnapshot()
        XCTAssertTrue(snapshot.categoryCatalog.groups.contains { $0.level2 == "Men's Shoes" })
    }

    private func writeTemporaryTSV(_ contents: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
