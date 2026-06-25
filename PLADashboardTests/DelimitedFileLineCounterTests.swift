import XCTest
@testable import PLADashboard

final class DelimitedFileLineCounterTests: XCTestCase {
    func testEstimateDataRowCountMatchesMerchantSample() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SampleMerchant", withExtension: "tsv")
        )
        let estimate = try DelimitedFileLineCounter.estimateDataRowCount(fileURL: url)
        XCTAssertEqual(estimate, 5)
    }

    func testEstimateDataRowCountMatchesSelfBuiltMerchantSample() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SampleMerchantSelfBuilt", withExtension: "tsv")
        )
        let estimate = try DelimitedFileLineCounter.estimateDataRowCount(fileURL: url)
        XCTAssertEqual(estimate, 5)
    }

    func testEstimateDataRowCountRespectsLinesToSkip() throws {
        let contents = """
        skip line 1
        skip line 2
        header\tvalue
        row1\ta
        row2\tb

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let estimate = try DelimitedFileLineCounter.estimateDataRowCount(
            fileURL: url,
            linesToSkip: 2
        )
        XCTAssertEqual(estimate, 2)
    }
}
