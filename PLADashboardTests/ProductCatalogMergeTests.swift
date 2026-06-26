import XCTest
@testable import PLADashboard

final class ProductCatalogMergeTests: XCTestCase {
    func testPickBetterImageURLPrefersURLWithoutQuery() {
        let withQuery =
            "http://litbimg.rightinthebox.com/images/sample.jpg?f=0"
        let withoutQuery =
            "http://litbimg.rightinthebox.com/images/sample.jpg"
        XCTAssertEqual(
            ProductCatalogMerge.pickBetterImageURL(withQuery, withoutQuery),
            withoutQuery
        )
    }

    func testPickBetterImageURLPrefersHTTPS() {
        let http = "http://litbimg.rightinthebox.com/images/sample.jpg"
        let https = "https://litbimg.rightinthebox.com/images/sample.jpg"
        XCTAssertEqual(
            ProductCatalogMerge.pickBetterImageURL(http, https),
            https
        )
    }
}
