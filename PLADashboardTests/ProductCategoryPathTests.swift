import XCTest
@testable import PLADashboard

final class ProductCategoryPathTests: XCTestCase {
    private let selfBuiltSample =
        "Shoes & Bags c3349_ > Men's Shoes c16445_ > Men's Sandals c37219_ > Outdoor Sandals c123985_"

    func testSelfBuiltDisplayNameStripsCategoryCode() {
        XCTAssertEqual(
            ProductCategoryPath.displayName(fromSelfBuiltSegment: "Shoes & Bags c3349_"),
            "Shoes & Bags"
        )
        XCTAssertEqual(
            ProductCategoryPath.displayName(fromSelfBuiltSegment: "Men's Shoes c16445_"),
            "Men's Shoes"
        )
    }

    func testSelfBuiltNormalizedStoragePath() {
        XCTAssertEqual(
            ProductCategoryPath.normalizedForStorage(selfBuiltSample, accountKind: .selfBuilt),
            "Shoes & Bags > Men's Shoes > Men's Sandals > Outdoor Sandals"
        )
    }

    func testThirdPartyNormalizedStoragePath() {
        let raw = "Apparel & Accessories > Clothing > Dresses"
        XCTAssertEqual(
            ProductCategoryPath.normalizedForStorage(raw, accountKind: .thirdParty),
            raw
        )
    }

    func testCategoryColumnNameByAccountKind() {
        XCTAssertEqual(
            ProductCategoryPath.categoryColumnName(for: .thirdParty),
            "google 商品类别"
        )
        XCTAssertEqual(
            ProductCategoryPath.categoryColumnName(for: .selfBuilt),
            "类型"
        )
    }

    func testCatalogBuildFromLegacySelfBuiltStoredPath() {
        let catalog = GoogleProductCategoryCatalog.build(fromCategoryPaths: [selfBuiltSample])
        XCTAssertTrue(catalog.groups.contains { $0.level2 == "Men's Shoes" })
        XCTAssertTrue(
            catalog.groups.first(where: { $0.level2 == "Men's Shoes" })?.level3.contains("Men's Sandals") == true
        )
    }
}
