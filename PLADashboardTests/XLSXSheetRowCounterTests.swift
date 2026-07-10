import XCTest
@testable import PLADashboard

final class XLSXSheetRowCounterTests: XCTestCase {
    func testEstimateFromDimensionAttribute() throws {
        let xml = """
        <?xml version="1.0"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <dimension ref="A1:AA168472"/>
        <sheetData>
        <row r="1"></row>
        </sheetData>
        </worksheet>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let estimate = try XLSXSheetRowCounter.estimateDataRowCount(sheetXMLURL: url)
        XCTAssertEqual(estimate, 168_471)
    }

    func testEstimateFallsBackToRowTagCount() throws {
        let xml = """
        <?xml version="1.0"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        <row r="1"></row>
        <row r="2"></row>
        <row r="3"></row>
        </sheetData>
        </worksheet>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let estimate = try XLSXSheetRowCounter.estimateDataRowCount(sheetXMLURL: url)
        XCTAssertEqual(estimate, 2)
    }

    func testEstimateFromSharedStringsFixture() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SamplePlaDeliveryDetailSharedStrings.xlsx")
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla-count-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sheetURL = temp.appendingPathComponent("sheet1.xml")
        try ZipEntryExtractor.extractEntry(
            named: "xl/worksheets/sheet1.xml",
            from: fixture,
            to: sheetURL
        )
        let estimate = try XLSXSheetRowCounter.estimateDataRowCount(sheetXMLURL: sheetURL)
        XCTAssertEqual(estimate, 1)
    }
}
