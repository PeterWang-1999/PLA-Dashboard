import XCTest
@testable import PLADashboard

final class WorkspaceAccountPersistenceTests: XCTestCase {
    private var workspaceRoot: URL!

    override func setUpWithError() throws {
        workspaceRoot = try WorkspaceTestSupport.setUpTemporaryWorkspace()
    }

    override func tearDownWithError() throws {
        WorkspaceTestSupport.tearDownTemporaryWorkspace(root: workspaceRoot)
        workspaceRoot = nil
    }

    func testLoadOrCreateManifestOnFreshInstall() throws {
        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        XCTAssertEqual(manifest.accounts.count, 1)
        XCTAssertEqual(manifest.accounts[0].name, WorkspaceAccountPersistence.defaultFirstAccountName)
        XCTAssertEqual(manifest.accounts[0].kind, .thirdParty)
        XCTAssertEqual(manifest.activeAccountID, manifest.accounts[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try WorkspacePaths.manifestURL().path))
    }

    func testManifestRoundTrip() throws {
        let account = WorkspaceAccount.makeDefault(name: "测试账户", kind: .selfBuilt)
        let manifest = WorkspaceAccountsManifest(
            schemaVersion: WorkspaceAccountsManifest.currentSchemaVersion,
            activeAccountID: account.id,
            accounts: [account]
        )
        try WorkspaceAccountPersistence.save(manifest)
        let loaded = try XCTUnwrap(try WorkspaceAccountPersistence.load())
        XCTAssertEqual(loaded.schemaVersion, manifest.schemaVersion)
        XCTAssertEqual(loaded.activeAccountID, manifest.activeAccountID)
        XCTAssertEqual(loaded.accounts.count, manifest.accounts.count)
        XCTAssertEqual(loaded.accounts[0].id, manifest.accounts[0].id)
        XCTAssertEqual(loaded.accounts[0].name, manifest.accounts[0].name)
        XCTAssertEqual(loaded.accounts[0].kind, manifest.accounts[0].kind)
    }

    func testValidateRejectsDuplicateAccountIDs() {
        let account = WorkspaceAccount.makeDefault(name: "A", kind: .thirdParty)
        let manifest = WorkspaceAccountsManifest(
            schemaVersion: WorkspaceAccountsManifest.currentSchemaVersion,
            activeAccountID: account.id,
            accounts: [account, account]
        )
        XCTAssertThrowsError(try manifest.validate())
    }

    func testValidateRejectsInvalidActiveAccountID() {
        let account = WorkspaceAccount.makeDefault(name: "A", kind: .thirdParty)
        let manifest = WorkspaceAccountsManifest(
            schemaVersion: WorkspaceAccountsManifest.currentSchemaVersion,
            activeAccountID: "missing",
            accounts: [account]
        )
        XCTAssertThrowsError(try manifest.validate())
    }

    func testCreateAccountCreatesDirectory() throws {
        _ = try WorkspaceAccountPersistence.loadOrCreateManifest()
        let account = try WorkspaceAccountPersistence.createAccount(name: "品牌 B", kind: .thirdParty)
        let accountDirectory = try WorkspacePaths.accountDirectory(id: account.id)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: accountDirectory.path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)

        let manifest = try XCTUnwrap(try WorkspaceAccountPersistence.load())
        XCTAssertEqual(manifest.accounts.count, 2)
        XCTAssertFalse(manifest.activeAccountID == account.id)
    }
}
