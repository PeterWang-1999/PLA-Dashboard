import XCTest
@testable import PLADashboard

@MainActor
final class DashboardVisiblePageTests: XCTestCase {
    private func makeModel(_ probe: PageQueryProbe) throws -> DashboardViewModel {
        let model = DashboardViewModel(
            followsVisiblePage: true,
            pageLoader: { _, _, _, _ in
                await probe.page()
                return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1, weekStarts: [], latestDataDay: nil)
            },
            chartLoader: { _, _, _ in
                await probe.chart()
                return .empty
            }
        )
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting())
        return model
    }

    func testReadyWhileChartVisibleLoadsOnlyChart() async throws {
        let probe = PageQueryProbe()
        let model = try makeModel(probe)
        model.setVisiblePage(.dataDashboard)
        await model.handleImportCompleted()
        let counts = await probe.counts
        XCTAssertEqual(counts.pages, 0)
        XCTAssertEqual(counts.charts, 1)
        XCTAssertFalse(model.isLoadingDataDashboard)
    }

    func testChartFilterChangesDoNotQueryHiddenTable() async throws {
        let loaded = expectation(description: "chart loaded")
        let probe = PageQueryProbe(onChart: loaded)
        let model = try makeModel(probe)
        model.setVisiblePage(.dataDashboard)
        model.bootstrapDataSource(hasMetrics: true)
        model.searchText = "latest"
        model.onSearchTextChanged()
        model.onFiltersChanged() // 与搜索防抖合并为最后一次请求。
        await fulfillment(of: [loaded], timeout: 3)
        await model.refreshData() // 隐藏产品页入口也不会查询。
        let counts = await probe.counts
        XCTAssertEqual(counts.pages, 0)
        XCTAssertEqual(counts.charts, 1)
    }

    func testSettingsWhileChartVisibleRefreshOnlyChart() async throws {
        let loaded = expectation(description: "chart refreshed after settings")
        let probe = PageQueryProbe(onChart: loaded)
        let model = try makeModel(probe)
        model.setVisiblePage(.dataDashboard)
        model.bootstrapDataSource(hasMetrics: true)
        model.handleSettingsDidChange()
        await fulfillment(of: [loaded], timeout: 3)
        let counts = await probe.counts
        XCTAssertEqual(counts.pages, 0)
        XCTAssertEqual(counts.charts, 1)
    }

    func testImportPageDefersQueriesUntilReturnToProducts() async throws {
        let loaded = expectation(description: "product page refreshed on return")
        let probe = PageQueryProbe(onPage: loaded)
        let model = try makeModel(probe)
        model.setVisiblePage(.imports)
        await model.handleImportCompleted()
        model.searchText = "new filters"
        model.onFiltersChanged()
        let hiddenCounts = await probe.counts
        XCTAssertEqual(hiddenCounts.pages, 0)
        XCTAssertEqual(hiddenCounts.charts, 0)
        model.setVisiblePage(.dashboard)
        await fulfillment(of: [loaded], timeout: 3)
        let counts = await probe.counts
        XCTAssertEqual(counts.pages, 1)
        XCTAssertEqual(counts.charts, 0)
    }

    func testBootstrapOnChartPageDoesNotFetchProductPage() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 20, merchantRows: 1)
        let probe = PageQueryProbe()
        let model = try makeModel(probe)
        model.configure(databaseClient: client)
        model.setVisiblePage(.dataDashboard)
        await model.bootstrapDashboard()
        let counts = await probe.counts
        XCTAssertEqual(counts.pages, 0)
        XCTAssertEqual(counts.charts, 1)
        XCTAssertFalse(model.isLoading)
    }

    func testLeavingChartPageRejectsLateChartResult() async throws {
        let started = expectation(description: "old chart started")
        let loader = SuspendedChartLoader(started: started)
        let model = DashboardViewModel(
            followsVisiblePage: true,
            chartLoader: { _, _, _ in try await loader.load() }
        )
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting())
        model.setVisiblePage(.dataDashboard)
        model.bootstrapDataSource(hasMetrics: true)
        let old = Task { await model.refreshDataDashboard() }
        await fulfillment(of: [started], timeout: 3)
        model.setVisiblePage(.imports)
        var stale = DataDashboardSnapshot.empty
        stale.reportingPeriodLabel = "stale chart"
        await loader.finish(stale)
        await old.value
        XCTAssertNotEqual(model.dataDashboardSnapshot.reportingPeriodLabel, "stale chart")
        XCTAssertFalse(model.isLoadingDataDashboard)
    }

    func testRebuildBroadcastsWithoutLocalDuplicateQueries() async throws {
        let probe = PageQueryProbe()
        let model = try makeModel(probe)
        model.setVisiblePage(.imports)
        var broadcasts = 0
        await model.rebuildMetricsAndRefresh { broadcasts += 1 }
        let counts = await probe.counts
        XCTAssertEqual(broadcasts, 1)
        XCTAssertEqual(counts.pages, 0)
        XCTAssertEqual(counts.charts, 0)
        XCTAssertFalse(model.isLoading)
    }

    func testSharedDataRevisionAcceptsOnlyCurrentAccount() async throws {
        let root = try WorkspaceTestSupport.setUpTemporaryWorkspace()
        defer { WorkspaceTestSupport.tearDownTemporaryWorkspace(root: root) }
        let store = AccountStore()
        await store.bootstrap()
        let id = try XCTUnwrap(store.activeAccountID)
        store.notifyDataChanged(accountID: "stale-account")
        XCTAssertEqual(store.dataRevision, 0)
        store.notifyDataChanged(accountID: id)
        XCTAssertEqual(store.dataRevision, 1)
        let other = try await store.createAccount(name: "Other")
        try await store.switchAccount(to: other.id)
        store.notifyDataChanged(accountID: id)
        XCTAssertEqual(store.dataRevision, 1)
        store.notifyDataChanged(accountID: other.id)
        XCTAssertEqual(store.dataRevision, 2)
    }
}

private actor PageQueryProbe {
    private var pages = 0
    private var charts = 0
    private let onPage: XCTestExpectation?
    private let onChart: XCTestExpectation?
    init(onPage: XCTestExpectation? = nil, onChart: XCTestExpectation? = nil) {
        self.onPage = onPage
        self.onChart = onChart
    }
    var counts: (pages: Int, charts: Int) { (pages, charts) }
    func page() { pages += 1; onPage?.fulfill() }
    func chart() { charts += 1; onChart?.fulfill() }
}

private actor SuspendedChartLoader {
    let started: XCTestExpectation
    private var pending: CheckedContinuation<DataDashboardSnapshot, Error>?
    init(started: XCTestExpectation) { self.started = started }
    func load() async throws -> DataDashboardSnapshot {
        try await withCheckedThrowingContinuation {
            pending = $0
            started.fulfill()
        }
    }
    func finish(_ snapshot: DataDashboardSnapshot) {
        pending?.resume(returning: snapshot)
        pending = nil
    }
}
