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
        let revisionBefore = store.workspaceRevision

        try await store.switchAccount(to: accountB.id)

        XCTAssertEqual(store.activeAccountID, accountB.id)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, accountB.id)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, store.activeAccountID)
        XCTAssertNotEqual(clientBeforeID, accountB.id)
        XCTAssertGreaterThan(store.workspaceRevision, revisionBefore)
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
        let revisionBefore = store.workspaceRevision

        try await store.switchAccount(to: activeID)

        XCTAssertEqual(store.activeDatabaseClient?.accountID, clientBeforeID)
        XCTAssertEqual(store.workspaceRevision, revisionBefore)
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

    func testSharedImportBlocksSwitchWithoutWindowLocalFlag() async throws {
        let store = AccountStore()
        await store.bootstrap()
        let accountID = try XCTUnwrap(store.activeAccountID)
        let accountB = try await store.createAccount(name: "账户 B")
        let revision = store.workspaceRevision
        let operationID = try store.beginImport(accountID: accountID, workspaceRevision: revision)

        do {
            try await store.switchAccount(to: accountB.id)
            XCTFail("另一窗口未传入本地导入状态，也必须阻止切换")
        } catch {
            guard case WorkspaceAccountError.importInProgress = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(store.activeAccountID, accountID)
        XCTAssertEqual(store.workspaceRevision, revision)
        XCTAssertEqual(try WorkspaceAccountPersistence.load()?.activeAccountID, accountID)

        store.endImport(operationID)
        try await store.switchAccount(to: accountB.id)
        XCTAssertEqual(store.activeAccountID, accountB.id)
    }

    func testSecondImportAndStaleCompletionCannotReleaseActiveImport() async throws {
        let store = AccountStore()
        await store.bootstrap()
        let accountID = try XCTUnwrap(store.activeAccountID)
        let revision = store.workspaceRevision
        let first = try store.beginImport(accountID: accountID, workspaceRevision: revision)
        XCTAssertThrowsError(try store.beginImport(accountID: accountID, workspaceRevision: revision))
        store.endImport(first)

        let second = try store.beginImport(accountID: accountID, workspaceRevision: revision)
        store.endImport(first)
        XCTAssertTrue(store.isImportInProgress)
        store.endImport(second)
        XCTAssertFalse(store.isImportInProgress)
    }

    func testImportViewModelsShareReservationAndReleaseAfterFailure() async throws {
        let store = AccountStore()
        await store.bootstrap()
        let client = try XCTUnwrap(store.activeDatabaseClient)
        let firstWindow = ImportViewModel()
        let secondWindow = ImportViewModel()
        for model in [firstWindow, secondWindow] {
            model.configure(
                databaseClient: client,
                accountStore: store,
                capabilities: WorkspaceCapabilities.forKind(.thirdParty),
                accountKind: .thirdParty,
                onReloadFilterCatalogs: {},
                onImportCompleted: {}
            )
        }
        let missingFile = workspaceRoot.appendingPathComponent("missing.tsv")
        firstWindow.handleImportedURLs([missingFile])
        // 任务尚未运行，保护也必须已经生效。
        XCTAssertTrue(store.isImportInProgress)
        XCTAssertTrue(firstWindow.isImporting)
        secondWindow.handleImportedURLs([missingFile])
        XCTAssertFalse(secondWindow.isImporting)
        XCTAssertNotNil(secondWindow.errorMessage)

        for _ in 0..<200 where store.isImportInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isImportInProgress)
        XCTAssertFalse(firstWindow.isImporting)
        XCTAssertNotNil(firstWindow.errorMessage)
    }

    func testImportRejectsStaleWorkspaceAndInFlightAccountSwitch() async throws {
        let store = AccountStore()
        await store.bootstrap()
        let originalID = try XCTUnwrap(store.activeAccountID)
        let originalRevision = store.workspaceRevision
        let accountB = try await store.createAccount(name: "账户 B")

        let switchTask = Task { try await store.switchAccount(to: accountB.id) }
        // 让切换进入首个 await；此时导入不能占用即将切换的工作区。
        for _ in 0..<100 where !store.isSwitchingAccount && store.activeAccountID == originalID {
            await Task.yield()
        }
        XCTAssertThrowsError(try store.beginImport(
            accountID: originalID, workspaceRevision: originalRevision
        ))
        try await switchTask.value
        XCTAssertThrowsError(try store.beginImport(
            accountID: originalID, workspaceRevision: originalRevision
        ))
        XCTAssertFalse(store.isImportInProgress)
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
        let account = try await store.createAccount(name: "新建店铺", kind: .thirdParty)

        XCTAssertEqual(store.accounts.count, initialCount + 1)
        XCTAssertEqual(account.name, "新建店铺")
        XCTAssertEqual(account.kind, .thirdParty)
        XCTAssertTrue(store.accounts.contains(where: { $0.id == account.id }))
    }

    func testCreateAccountRequiresReadyPhase() async throws {
        let store = AccountStore()

        do {
            _ = try await store.createAccount(name: "测试", kind: .thirdParty)
            XCTFail("Expected invalidManifest")
        } catch {
            guard case WorkspaceAccountError.invalidManifest = error else {
                return XCTFail("Unexpected error: \(error)")
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

        let accountB = try await store.createAccount(name: "隔离账户", kind: .thirdParty)
        try await store.switchAccount(to: accountB.id)

        let clientB = try XCTUnwrap(store.activeDatabaseClient)
        let productsB = try await clientB.fetchProducts(ids: ["10416614474003"])
        XCTAssertTrue(productsB.isEmpty)
    }

    func testThirdPartyCapabilitiesExcludeSalesReport() async {
        let store = AccountStore()
        await store.bootstrap()

        let capabilities = store.activeCapabilities
        XCTAssertNotNil(capabilities)
        XCTAssertFalse(capabilities?.importSourceKinds.contains(.salesReport) ?? true)
    }

    func testSelfBuiltAccountCanImportSampleSales() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let account = try await store.createAccount(name: "自建店", kind: .selfBuilt)
        try await store.switchAccount(to: account.id)

        let capabilities = try XCTUnwrap(store.activeCapabilities)
        XCTAssertTrue(capabilities.importSourceKinds.contains(.salesReport))

        guard let sampleURL = Bundle.main.url(forResource: "SampleSales", withExtension: "csv") else {
            XCTFail("未找到内置样例文件 SampleSales.csv")
            return
        }

        let client = try XCTUnwrap(store.activeDatabaseClient)
        let importer = SalesReportImporter(databaseClient: client)
        let result = try await importer.importFile(sourceURL: sampleURL) { _ in }

        let rowCount = try await client.countSalesDaily(importId: result.importId)
        XCTAssertGreaterThan(rowCount, 0)
        XCTAssertEqual(result.job.sourceKind, ImportSourceKind.salesReport.rawValue)
    }
}
