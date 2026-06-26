import XCTest
@testable import PLADashboard

final class ProductImageURLResolverTests: XCTestCase {
    func testResolvesHTTPSURL() {
        let url = ProductImageURLResolver.resolve(
            "https://cdn.shopify.com/s/files/1/0887/9364/5331/files/sample.jpg?v=1"
        )
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertTrue(url?.absoluteString.contains("cdn.shopify.com") == true)
    }

    func testAddsHTTPSForHostOnlyURL() {
        let url = ProductImageURLResolver.resolve(
            "litb-cgis.rightinthebox.com/images/800x800/sample.jpg"
        )
        XCTAssertEqual(url?.absoluteString, "https://litb-cgis.rightinthebox.com/images/800x800/sample.jpg")
    }

    func testAddsHTTPSForProtocolRelativeURL() {
        let url = ProductImageURLResolver.resolve("//cdn.example.com/image.jpg")
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/image.jpg")
    }

    func testRejectsRelativePath() {
        XCTAssertNil(ProductImageURLResolver.resolve("/images/sample.jpg"))
    }

    func testRejectsEmptyAndWhitespace() {
        XCTAssertNil(ProductImageURLResolver.resolve(nil))
        XCTAssertNil(ProductImageURLResolver.resolve(""))
        XCTAssertNil(ProductImageURLResolver.resolve("   "))
    }
}
