import XCTest
@testable import PLADashboard

final class ImportUserFacingErrorTests: XCTestCase {
    func testMapsGenericFileOpenFailure() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 260,
            userInfo: [NSLocalizedDescriptionKey: "The file couldn't be opened."]
        )
        let message = ImportUserFacingError.message(for: error, phase: .stagingBookmark)
        XCTAssertTrue(message.contains("保存导入记录"))
        XCTAssertFalse(message.contains("The file couldn't be opened."))
    }

    func testPreservesLocalizedImportErrors() {
        let error = ImportTextNormalizationError.fileTooLargeForTranscode(size: 271 * 1024 * 1024)
        let message = ImportUserFacingError.message(for: error)
        XCTAssertTrue(message.contains("UTF-8"))
    }
}
