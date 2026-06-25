import XCTest
@testable import PLADashboard

@MainActor
final class DashboardViewModelAccountSwitchTests: XCTestCase {
    private var workspaceRoot: URL!

    private let sampleAdsCSV = """
Ador - 产品数据
2026-06-01 - 2026-06-22
天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
2026-06-20\tshopify_ZZ_10416614474003_54238242767123\tCampaign A\tUSD\t12.34\t1000\t50\t2.5\t$99.00
"""

    override func setUpWithError() throws {
        workspaceRoot = try WorkspaceTestSupport.setUpTemporaryWorkspace()
    }

    override func tearDownWithError() throws {
        WorkspaceTestSupport.tearDownTemporaryWorkspace(root: workspaceRoot)
        workspaceRoot = nil
    }

    func testResetClearsPagination() async throws {
        let viewModel = DashboardViewModel()
        viewModel.bootstrapDataSource(hasMetrics: true)
        viewModel.totalPages = 25

        viewModel.resetForAccountSwitch()

        XCTAssertEqual(viewModel.totalPages, 1)
        XCTAssertTrue(viewModel.showsEmptyState)
    }

    func testResetClearsFilterCatalogs() {
        let viewModel = DashboardViewModel()
        viewModel.customLabelCatalog = .loadBundled()
        viewModel.categoryCatalog = .loadBundled()

        viewModel.resetForAccountSwitch()

        XCTAssertEqual(viewModel.customLabelCatalog, .empty)
        XCTAssertEqual(viewModel.categoryCatalog, .empty)
        XCTAssertEqual(viewModel.selectedCustomLabelFilter, .all)
        XCTAssertEqual(viewModel.selectedCategoryFilter, .all)
    }

    func testFilterCatalogsDifferBetweenAccounts() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let accountA = try XCTUnwrap(store.activeAccountID)
        let clientA = try XCTUnwrap(store.activeDatabaseClient)
        try await importMerchantData(
            into: clientA,
            customLabel2: "ador-alpha",
            productID: "shopify_ZZ_10416614474003_54238242767123"
        )
        try await importAdsData(into: clientA)
        try await clientA.rebuildProductWeeklyMetrics()

        let accountB = try store.createAccount(name: "SHO", kind: .thirdParty)
        let clientB = try DatabaseClient.make(accountID: accountB.id)
        try await importMerchantData(
            into: clientB,
            customLabel2: "sho-beta",
            productID: "shopify_ZZ_99999999999999_11111111111111"
        )

        let viewModel = DashboardViewModel()
        await reloadWorkspace(into: viewModel, from: store, client: clientA)
        let catalogA = viewModel.customLabelCatalog
        XCTAssertTrue(
            catalogA.groups.first(where: { $0.columnName == "自定义标签 2" })?.values.contains("ador-alpha") == true
        )

        try await store.switchAccount(to: accountB.id)
        await reloadWorkspace(into: viewModel, from: store, client: clientB)
        let catalogB = viewModel.customLabelCatalog
        XCTAssertTrue(
            catalogB.groups.first(where: { $0.columnName == "自定义标签 2" })?.values.contains("sho-beta") == true
        )
        XCTAssertFalse(
            catalogB.groups.first(where: { $0.columnName == "自定义标签 2" })?.values.contains("ador-alpha") == true
        )

        try await store.switchAccount(to: accountA)
        await reloadWorkspace(into: viewModel, from: store, client: clientA)
        XCTAssertTrue(
            viewModel.customLabelCatalog.groups.first(where: { $0.columnName == "自定义标签 2" })?
                .values.contains("ador-alpha") == true
        )
    }

    func testStaleCatalogLoadIsIgnoredAfterAccountSwitch() async throws {
        let populatedClient = try DatabaseClient.makeInMemoryForTesting()
        try await importSampleData(into: populatedClient)

        let emptyClient = try DatabaseClient.makeInMemoryForTesting()

        let viewModel = DashboardViewModel()
        viewModel.configure(databaseClient: populatedClient)
        viewModel.customLabelCatalog = .empty

        let catalogTask = Task {
            await viewModel.reloadFilterCatalogsFromDatabase()
        }
        viewModel.resetForAccountSwitch()
        viewModel.configure(databaseClient: emptyClient)
        await viewModel.reloadFilterCatalogsFromDatabase()
        await catalogTask.value

        let label0Values = viewModel.customLabelCatalog.groups
            .first(where: { $0.columnName == "自定义标签 0" })?.values ?? []
        XCTAssertTrue(label0Values.isEmpty, "过期 catalog 加载结果不应写回当前空账户")
    }

    func testSwitchToEmptyAccountShowsEmptyState() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let populatedClient = try XCTUnwrap(store.activeDatabaseClient)
        try await importSampleData(into: populatedClient)

        let emptyAccount = try store.createAccount(name: "空账户", kind: .thirdParty)
        let emptyClient = try DatabaseClient.make(accountID: emptyAccount.id)

        let viewModel = DashboardViewModel()
        await simulateAccountLoad(viewModel: viewModel, client: populatedClient)
        XCTAssertFalse(viewModel.showsEmptyState)
        XCTAssertFalse(viewModel.rows.isEmpty)

        await simulateAccountLoad(viewModel: viewModel, client: emptyClient)
        XCTAssertTrue(viewModel.showsEmptyState)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.totalPages, 1)
    }

    func testSwitchBackToPopulatedAccountShowsData() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let populatedClient = try XCTUnwrap(store.activeDatabaseClient)
        try await importSampleData(into: populatedClient)

        let emptyAccount = try store.createAccount(name: "空账户", kind: .thirdParty)
        let emptyClient = try DatabaseClient.make(accountID: emptyAccount.id)

        let viewModel = DashboardViewModel()
        await simulateAccountLoad(viewModel: viewModel, client: populatedClient)
        XCTAssertFalse(viewModel.rows.isEmpty)

        await simulateAccountLoad(viewModel: viewModel, client: emptyClient)
        XCTAssertTrue(viewModel.showsEmptyState)

        await simulateAccountLoad(viewModel: viewModel, client: populatedClient)
        XCTAssertFalse(viewModel.showsEmptyState)
        XCTAssertFalse(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.rows.first?.id, "10416614474003")
    }

    func testAccountStoreSwitchThenDashboardReloadShowsCorrectData() async throws {
        let store = AccountStore()
        await store.bootstrap()

        let defaultAccountID = try XCTUnwrap(store.activeAccountID)
        let populatedClient = try XCTUnwrap(store.activeDatabaseClient)
        try await importSampleData(into: populatedClient)

        let viewModel = DashboardViewModel()
        await reloadWorkspace(into: viewModel, from: store)
        XCTAssertFalse(viewModel.showsEmptyState)

        let emptyAccount = try store.createAccount(name: "空账户", kind: .thirdParty)
        try await store.switchAccount(to: emptyAccount.id)
        await reloadWorkspace(into: viewModel, from: store)
        XCTAssertTrue(viewModel.showsEmptyState)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, emptyAccount.id)

        try await store.switchAccount(to: defaultAccountID)
        await reloadWorkspace(into: viewModel, from: store)
        XCTAssertFalse(viewModel.showsEmptyState)
        XCTAssertFalse(viewModel.rows.isEmpty)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, defaultAccountID)
    }

    func testStaleRefreshResultIsIgnoredAfterAccountSwitch() async throws {
        let populatedClient = try DatabaseClient.makeInMemoryForTesting()
        try await importSampleData(into: populatedClient)

        let emptyClient = try DatabaseClient.makeInMemoryForTesting()

        let viewModel = DashboardViewModel()
        viewModel.configure(databaseClient: populatedClient)
        viewModel.bootstrapDataSource(hasMetrics: true)

        let refreshTask = Task {
            await viewModel.refreshData()
        }
        viewModel.resetForAccountSwitch()
        viewModel.configure(databaseClient: emptyClient)
        await viewModel.bootstrapDashboard()
        await refreshTask.value

        XCTAssertTrue(viewModel.showsEmptyState)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.totalPages, 1)
    }

    func testStaleBootstrapResultIsIgnoredAfterAccountSwitch() async throws {
        let populatedClient = try DatabaseClient.makeInMemoryForTesting()
        try await importSampleData(into: populatedClient)

        let emptyClient = try DatabaseClient.makeInMemoryForTesting()

        let viewModel = DashboardViewModel()
        viewModel.configure(databaseClient: populatedClient)

        let bootstrapTask = Task {
            await viewModel.bootstrapDashboard()
        }
        viewModel.resetForAccountSwitch()
        viewModel.configure(databaseClient: emptyClient)
        await viewModel.bootstrapDashboard()
        await bootstrapTask.value

        XCTAssertTrue(viewModel.showsEmptyState)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    private func simulateAccountLoad(
        viewModel: DashboardViewModel,
        client: DatabaseClient
    ) async {
        viewModel.resetForAccountSwitch()
        viewModel.configure(databaseClient: client) {
            await viewModel.bootstrapDashboard()
        }
        await viewModel.reloadFilterCatalogsFromDatabase()
        await viewModel.bootstrapDashboard()
    }

    private func reloadWorkspace(
        into viewModel: DashboardViewModel,
        from store: AccountStore,
        client: DatabaseClient? = nil
    ) async {
        let databaseClient: DatabaseClient
        if let client {
            databaseClient = client
        } else {
            guard let activeAccountID = store.activeAccountID,
                  let activeClient = store.activeDatabaseClient,
                  activeClient.accountID == activeAccountID else {
                XCTFail("账户 manifest 与 database client 未同步")
                return
            }
            databaseClient = activeClient
        }

        viewModel.resetForAccountSwitch()
        viewModel.configure(databaseClient: databaseClient) {
            await viewModel.bootstrapDashboard()
        }
        await viewModel.reloadFilterCatalogsFromDatabase()
        await viewModel.bootstrapDashboard()
    }

    private func merchantTSV(customLabel2: String, productID: String) -> String {
        """
标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
Sample Dress\t\(productID)\thttps://example.com/dress\thttps://example.com/dress.jpg\tEN\t\t\(customLabel2)\t\t\tApparel & Accessories > Clothing > Dresses
"""
    }

    private func importMerchantData(
        into client: DatabaseClient,
        customLabel2: String,
        productID: String
    ) async throws {
        let merchantURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tsv")
        try merchantTSV(customLabel2: customLabel2, productID: productID)
            .write(to: merchantURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: merchantURL) }

        _ = try await MerchantCenterImporter(databaseClient: client)
            .importFile(sourceURL: merchantURL) { _ in }
    }

    private func importAdsData(into client: DatabaseClient) async throws {
        let adsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try sampleAdsCSV.write(to: adsURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: adsURL) }

        _ = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
    }

    private func importSampleData(into client: DatabaseClient) async throws {
        try await importMerchantData(
            into: client,
            customLabel2: "",
            productID: "shopify_ZZ_10416614474003_54238242767123"
        )
        try await importAdsData(into: client)
        try await client.rebuildProductWeeklyMetrics()
    }
}
