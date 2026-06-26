import XCTest
@testable import PLADashboard

final class ImportTextEncodingTests: XCTestCase {
    func testDetectGBKWithoutBOM() {
        let gbkHeader = "日期,LSIN\n"
        guard let data = gbkHeader.data(using: ImportTextEncoding.gb18030) else {
            XCTFail("GB18030 encoding unavailable")
            return
        }
        XCTAssertEqual(ImportTextEncoding.detect(preview: data), .gb18030)
    }

    func testDetectUTF16LittleEndianBOM() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00, 0x64, 0x00])
        XCTAssertEqual(ImportTextEncoding.detect(preview: data), .utf16LittleEndian)
    }

    func testNormalizeGBKFileToUTF8() throws {
        let csv = """
日期,LSIN,Gross Sales($)
2026-06-20,S14429548,$100.00
"""
        guard let gbkData = csv.data(using: ImportTextEncoding.gb18030) else {
            XCTFail("GB18030 encoding unavailable")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try gbkData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertTrue(try ImportTextEncoding.normalizeToUTF8IfNeeded(at: tempURL))

        let normalized = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(normalized.hasPrefix("日期,LSIN,Gross Sales($)"))
    }

    func testNormalizeUTF16FileToUTF8() throws {
        let csv = "天\t产品 ID\n2026-06-20\tshopify_zz_1\n"
        guard let utf16Data = csv.data(using: .utf16LittleEndian) else {
            XCTFail("UTF-16 LE encoding unavailable")
            return
        }
        var data = Data([0xFF, 0xFE])
        data.append(utf16Data)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertTrue(try ImportTextEncoding.normalizeToUTF8IfNeeded(at: tempURL))

        let normalized = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(normalized.contains("天\t产品 ID"))
    }

    func testUTF8FileUnchanged() throws {
        let csv = "日期,LSIN\n2026-06-20,S1\n"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let before = try Data(contentsOf: tempURL)
        XCTAssertFalse(try ImportTextEncoding.normalizeToUTF8IfNeeded(at: tempURL))
        let after = try Data(contentsOf: tempURL)
        XCTAssertEqual(before, after)
    }

    func testLargeUTF8FileDoesNotLoadEntireFileIntoMemory() throws {
        let line = String(repeating: "x", count: 1_024) + "\n"
        let repeatedLine = String(repeating: line, count: 8_192)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try Data(repeatedLine.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertFalse(try ImportTextEncoding.normalizeToUTF8IfNeeded(at: tempURL))
    }
}
