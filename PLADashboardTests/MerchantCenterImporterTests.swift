import XCTest
@testable import PLADashboard

final class MerchantCenterImporterTests: XCTestCase {
  private let sampleTSV = """
标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
Sample Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
Sample Shirt\t15091206_00002_US_en\thttps://example.com/shirt\thttps://example.com/shirt.jpg\tShopify产品\t\t\t\t\tApparel & Accessories > Clothing > Shirts & Tops
Invalid Row\t\thttps://example.com/missing\thttps://example.com/missing.jpg\t\t\t\t\t\tApparel & Accessories
"""

    func testImportSampleTSV() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try sampleTSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: databaseClient)
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
    }
}
