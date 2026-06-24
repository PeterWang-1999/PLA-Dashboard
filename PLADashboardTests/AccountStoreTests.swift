import XCTest
@testable import PLADashboard

@MainActor
final class AccountStoreTests: XCTestCase {
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

    func testBootstrapCreatesReadyPhase() async {
        let store = AccountStore()
        await store.bootstrap()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertNotNil(store.activeDatabaseClient)
        XCTAssertGreaterThanOrEqual(store.accounts.count, 1)
        XCTAssertNotNil(store.activeAccountID)
    }

    func testBootstrapOnFreshInstall() async {
        let store = AccountStore()
        await store.bootstrap()

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].name, WorkspaceAccountPersistence.defaultFirstAccountName)
        XCTAssertEqual(store.activeAccountID, store.accounts[0].id)
    }

    func testSwitchAccountUpdatesClient() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let accountB = try WorkspaceAccountPersistence.createAccount(name: "账户 B", kind: .thirdParty)
        let clientBeforeID = store.activeDatabaseClient?.accountID

        try await store.switchAccount(to: accountB.id)

        XCTAssertEqual(store.activeAccountID, accountB.id)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, accountB.id)
        XCTAssertNotEqual(clientBeforeID, accountB.id)
    }

    func testSwitchAccountPersistsActiveID() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let accountB = try WorkspaceAccountPersistence.createAccount(name: "账户 B", kind: .thirdParty)
        try await store.switchAccount(to: accountB.id)

        let reloaded = try XCTUnwrap(try WorkspaceAccountPersistence.load())
        XCTAssertEqual(reloaded.activeAccountID, accountB.id)

        let freshStore = AccountStore()
        await freshStore.bootstrap()
        XCTAssertEqual(freshStore.activeAccountID, accountB.id)
    }

    func testSwitchToSameAccountIsNoOp() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let activeID = try XCTUnwrap(store.activeAccountID)
        let clientBeforeID = store.activeDatabaseClient?.accountID

        try await store.switchAccount(to: activeID)

        XCTAssertEqual(store.activeDatabaseClient?.accountID, clientBeforeID)
    }

    func testSwitchAccountRejectsImportInProgress() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let accountB = try WorkspaceAccountPersistence.createAccount(name: "账户 B", kind: .thirdParty)

        do {
            try await store.switchAccount(to: accountB.id, isImportInProgress: true)
            XCTFail("Expected importInProgress")
        } catch {
            guard case WorkspaceAccountError.importInProgress = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testSwitchAccountIsolation() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let activeID = try XCTUnwrap(store.activeAccountID)
        let clientA = try XCTUnwrap(store.activeDatabaseClient)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try sampleTSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: clientA)
        _ = try await importer.importFile(sourceURL: tempURL) { _ in }

        let productsA = try await clientA.fetchProducts(ids: ["10416614474003"])
        XCTAssertEqual(productsA.count, 1)

        let accountB = try WorkspaceAccountPersistence.createAccount(name: "账户 B", kind: .thirdParty)
        try await store.switchAccount(to: accountB.id)

        let clientB = try XCTUnwrap(store.activeDatabaseClient)
        XCTAssertNotEqual(clientB.accountID, activeID)

        let productsB = try await clientB.fetchProducts(ids: ["10416614474003"])
        XCTAssertTrue(productsB.isEmpty)
    }

    func testCreateAccountAppendsToManifest() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let initialCount = store.accounts.count
        let account = try store.createAccount(name: "新建店铺", kind: .thirdParty)

        XCTAssertEqual(store.accounts.count, initialCount + 1)
        XCTAssertEqual(account.name, "新建店铺")
        XCTAssertEqual(account.kind, .thirdParty)
        XCTAssertTrue(store.accounts.contains(where: { $0.id == account.id }))
    }

    func testCreateAccountRequiresReadyPhase() async throws {
        let store = AccountStore()

        XCTAssertThrowsError(try store.createAccount(name: "测试", kind: .thirdParty)) { error in
            guard case WorkspaceAccountError.invalidManifest = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testCreateThenSwitchShowsIsolatedData() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let clientA = try XCTUnwrap(store.activeDatabaseClient)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try sampleTSV.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let importer = MerchantCenterImporter(databaseClient: clientA)
        _ = try await importer.importFile(sourceURL: tempURL) { _ in }

        let productsA = try await clientA.fetchProducts(ids: ["10416614474003"])
        XCTAssertEqual(productsA.count, 1)

        let accountB = try store.createAccount(name: "隔离账户", kind: .thirdParty)
        try await store.switchAccount(to: accountB.id)

        let clientB = try XCTUnwrap(store.activeDatabaseClient)
        let productsB = try await clientB.fetchProducts(ids: ["10416614474003"])
        XCTAssertTrue(productsB.isEmpty)
    }
}
