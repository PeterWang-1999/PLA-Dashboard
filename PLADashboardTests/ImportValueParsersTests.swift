import XCTest
@testable import PLADashboard

final class ImportValueParsersTests: XCTestCase {
    func testParseISODate() {
        XCTAssertEqual(ImportValueParsers.parseISODate("2026-06-20"), "2026-06-20")
        XCTAssertEqual(ImportValueParsers.parseISODate("2026/6/20"), "2026-06-20")
    }

    func testParseCurrencyToCents() {
        XCTAssertEqual(ImportValueParsers.parseCurrencyToCents("$1,234.56"), 123_456)
        XCTAssertEqual(ImportValueParsers.parseCurrencyToCents("99.00"), 9_900)
    }

    func testParseCostToMicros() {
        XCTAssertEqual(ImportValueParsers.parseCostToMicros("12.34"), 12_340_000)
    }

    func testParseIntegerAndDecimal() {
        XCTAssertEqual(ImportValueParsers.parseInteger("1,000"), 1000)
        XCTAssertEqual(ImportValueParsers.parseInteger("\"1,259\""), 1259)
        XCTAssertEqual(ImportValueParsers.parseDecimal("2.5"), 2.5)
        XCTAssertEqual(ImportValueParsers.parseCount("25401.0"), 25401)
        XCTAssertEqual(ImportValueParsers.parseCount("380"), 380)
    }
}
