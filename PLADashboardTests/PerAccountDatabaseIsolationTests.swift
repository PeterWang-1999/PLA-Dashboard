import XCTest
@testable import PLADashboard

final class PerAccountDatabaseIsolationTests: XCTestCase {
    private var workspaceRoot: URL!

    private let sampleTSV = """
标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
Sample Dress\tshopify_ZZ_10416614474003_54238242767123\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
"""

    override func setUpWithError() throws {
        workspaceRoot = try WorkspaceTestSupport.setUpTemporaryWorkspace()
    }

    override func tearDownWithError() throws {
        WorkspaceTestSupport.tearDownTemporaryWorkspace(root: workspaceRoot)
        workspaceRoot = nil
    }

    func testMerchantImportIsolatedBetweenAccounts() async throws {
        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        let accountB = try WorkspaceAccountPersistence.createAccount(name: "账户 B", kind: .thirdParty)

        let clientA = try DatabaseClient.make(accountID: manifest.activeAccountID)
        let clientB = try DatabaseClient.make(accountID: accountB.id)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try sampleTSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: clientA)
        _ = try await importer.importFile(sourceURL: tempURL) { _ in }

        let productsA = try await clientA.fetchProducts(ids: ["10416614474003"])
        XCTAssertEqual(productsA.count, 1)

        let productsB = try await clientB.fetchProducts(ids: ["10416614474003"])
        XCTAssertTrue(productsB.isEmpty)
    }

    func testImportStagingUsesAccountDirectory() async throws {
        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        let client = try DatabaseClient.make(accountID: manifest.activeAccountID)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try sampleTSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: client)
        let result = try await importer.importFile(sourceURL: tempURL) { _ in }

        let stagedDirectory = try WorkspacePaths.importsRoot(accountID: manifest.activeAccountID)
            .appendingPathComponent(result.importId, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedDirectory.path))
    }
}
