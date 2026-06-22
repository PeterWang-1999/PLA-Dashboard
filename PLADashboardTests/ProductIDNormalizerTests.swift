import XCTest
@testable import PLADashboard

final class ProductIDNormalizerTests: XCTestCase {
    func testShopifyFormat() {
        let result = ProductIDNormalizer.normalize("shopify_ZZ_10416614474003_54238242767123")
        XCTAssertEqual(result.productID, "10416614474003")
        XCTAssertEqual(result.variantID, "54238242767123")
        XCTAssertEqual(result.sourceFormat, .shopifyItemID)
        XCTAssertEqual(result.confidence, .high)
    }

    func testUnderscorePrefixFormat() {
        let result = ProductIDNormalizer.normalize("15091206_00002_US_en")
        XCTAssertEqual(result.productID, "15091206")
        XCTAssertNil(result.variantID)
        XCTAssertEqual(result.sourceFormat, .underscorePrefix)
        XCTAssertEqual(result.confidence, .medium)
    }

    func testEmptyValue() {
        let result = ProductIDNormalizer.normalize("   ")
        XCTAssertEqual(result.productID, "")
        XCTAssertEqual(result.sourceFormat, .empty)
    }
}
