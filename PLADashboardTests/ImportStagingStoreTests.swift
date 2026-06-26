import XCTest
@testable import PLADashboard

final class ImportStagingStoreTests: XCTestCase {
    func testStageCreatesMinimalBookmarkForContainerFile() async throws {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        let contents = "标题\t序号\t链接\t图片链接\nSample\tS1\thttps://example.com\thttps://example.com/a.jpg\n"
        try Data(contents.utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let staging = try ImportStagingStore.stage(
            sourceURL: sourceURL,
            accountID: databaseClient.accountID,
            importId: UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: staging.stagedFileURL.deletingLastPathComponent()) }

        let resolvedURL = try ImportStagingStore.resolveBookmark(staging.bookmarkData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedURL.path))
    }
}
