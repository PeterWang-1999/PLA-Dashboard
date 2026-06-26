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

    func testStripsAllQueryFromLitbimgURL() {
        let raw =
            "http://litbimg.rightinthebox.com/images/800x800/202109/bps/product/inc/mwyudz1632467780177.jpg?f=0"
        let url = ProductImageURLResolver.resolve(raw)
        XCTAssertEqual(url?.scheme, "http")
        XCTAssertEqual(url?.host, "litbimg.rightinthebox.com")
        XCTAssertNil(url?.query)
        XCTAssertEqual(
            url?.path,
            "/images/800x800/202109/bps/product/inc/mwyudz1632467780177.jpg"
        )
    }

    func testStripsReloadQueryFromLitbimgURL() {
        let raw =
            "http://litbimg.rightinthebox.com/images/sample.jpg?reload=1"
        let url = ProductImageURLResolver.resolve(raw)
        XCTAssertNil(url?.query)
    }

    func testStripsMixedQueryFromLitbimgURL() {
        let raw = "http://litbimg.rightinthebox.com/images/sample.jpg?v=2&f=1"
        let url = ProductImageURLResolver.resolve(raw)
        XCTAssertNil(url?.query)
    }

    func testPreservesShopifyQueryParameters() {
        let raw = "https://cdn.shopify.com/s/files/sample.jpg?v=1780033180"
        let url = ProductImageURLResolver.resolve(raw)
        XCTAssertEqual(url?.query, "v=1780033180")
    }
}
