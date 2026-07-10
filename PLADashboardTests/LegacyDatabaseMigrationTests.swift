import XCTest
import GRDB
@testable import PLADashboard

final class LegacyDatabaseMigrationTests: XCTestCase {
    private var workspaceRoot: URL!

    override func setUpWithError() throws {
        workspaceRoot = try WorkspaceTestSupport.setUpTemporaryWorkspace()
    }

    override func tearDownWithError() throws {
        WorkspaceTestSupport.tearDownTemporaryWorkspace(root: workspaceRoot)
        workspaceRoot = nil
    }

    func testMigrateLegacyDatabaseAndImports() async throws {
        let legacyDatabaseURL = try WorkspacePaths.legacyDatabaseURL()
        try await Self.seedLegacyDatabase(at: legacyDatabaseURL)

        let legacyImportsURL = try WorkspacePaths.legacyImportsRoot()
        try FileManager.default.createDirectory(at: legacyImportsURL, withIntermediateDirectories: true)
        let markerURL = legacyImportsURL.appendingPathComponent("marker.txt")
        try Data("legacy".utf8).write(to: markerURL)

        XCTAssertTrue(try LegacyDatabaseMigrator.needsMigration())

        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        XCTAssertEqual(manifest.accounts.count, 1)
        XCTAssertEqual(manifest.accounts[0].name, LegacyDatabaseMigrator.defaultMigratedAccountName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDatabaseURL.path))

        let migratedImportsURL = try WorkspacePaths.importsRoot(accountID: manifest.activeAccountID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedImportsURL.appendingPathComponent("marker.txt").path))

        let client = try DatabaseClient.make(accountID: manifest.activeAccountID)
        let products = try await client.fetchProducts(ids: ["legacy-product-1"])
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products[0].title, "Legacy")
    }

    private static func seedLegacyDatabase(at legacyDatabaseURL: URL) async throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
        }
        let queue = try DatabaseQueue(path: legacyDatabaseURL.path, configuration: config)
        try AppDatabaseMigrator.migrate(queue)
        let importedAt = ISO8601DateFormatter().string(from: Date())
        try await queue.write { db in
            let product = ProductRecord(
                productId: "legacy-product-1",
                title: "Legacy",
                canonicalLink: nil,
                imageUrl: nil,
                customLabel0: nil,
                customLabel1: nil,
                customLabel2: nil,
                customLabel3: nil,
                customLabel4: nil,
                lsin: nil,
                googleProductCategory: nil,
                firstListedAt: nil,
                firstSeenAt: importedAt,
                lastSeenAt: importedAt,
                updatedFromImportId: "legacy-import"
            )
            try product.insert(db)
        }
    }

    func testDoesNotMigrateTwice() throws {
        _ = try WorkspaceAccountPersistence.loadOrCreateManifest()
        let secondLoad = try WorkspaceAccountPersistence.loadOrCreateManifest()
        XCTAssertEqual(secondLoad.accounts.count, 1)
        XCTAssertFalse(try LegacyDatabaseMigrator.needsMigration())
    }

    func testMigrateMovesWALSidecarFiles() async throws {
        let legacyDatabaseURL = try WorkspacePaths.legacyDatabaseURL()
        try await Self.seedLegacyDatabase(at: legacyDatabaseURL)

        let walURL = URL(fileURLWithPath: legacyDatabaseURL.path + "-wal")
        if !FileManager.default.fileExists(atPath: walURL.path) {
            FileManager.default.createFile(atPath: walURL.path, contents: Data([0x01]))
        }

        let manifest = try LegacyDatabaseMigrator.migrate()
        let migratedDatabaseURL = try WorkspacePaths.databaseURL(accountID: manifest.activeAccountID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedDatabaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDatabaseURL.path))
    }
}
