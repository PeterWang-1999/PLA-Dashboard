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

    /// Product Sales 导出的毛利额常带 30+ 位小数；旧实现会把 cents 误算成 0。
    func testParseCurrencyToCentsWithUltraLongFraction() {
        XCTAssertEqual(
            ImportValueParsers.parseCurrencyToCents(
                "104.351501070163032066938202220754409954"
            ),
            10_435
        )
        XCTAssertEqual(
            ImportValueParsers.parseCurrencyToCents(
                "33.47256321945263118545977102507782541461"
            ),
            3_347
        )
        XCTAssertEqual(ImportValueParsers.parseCurrencyToCents("-209.374797"), -20_937)
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
