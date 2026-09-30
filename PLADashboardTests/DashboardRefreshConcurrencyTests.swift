import XCTest
@testable import PLADashboard

@MainActor
final class DashboardRefreshConcurrencyTests: XCTestCase {
    private func makeModel(
        pages: ControlledDashboardLoader<DashboardPageResult> = .init(),
        charts: ControlledDashboardLoader<DataDashboardSnapshot> = .init()
    ) throws -> DashboardViewModel {
        let model = DashboardViewModel(
            pageLoader: { _, _, _, _ in try await pages.load() },
            chartLoader: { _, _, _ in try await charts.load() }
        )
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting())
        model.bootstrapDataSource(hasMetrics: true)
        return model
    }

    private func page(_ rowIndex: Int) -> DashboardPageResult {
        DashboardPageResult(
            rows: [DashboardPreviewData.rows[rowIndex]], totalCount: 1, totalPages: 1,
            weekStarts: ["2026-09-20"], latestDataDay: "2026-09-26"
        )
    }

    func testOlderSuccessCannotReplaceNewerTableResult() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        let old = Task { await model.refreshData() }
        await loader.waitForRequest(1)
        let latest = Task { await model.refreshData() }
        await loader.waitForRequest(2)
        await loader.finish(2, with: .success(page(1)))
        await latest.value
        await loader.finish(1, with: .success(page(0)))
        await old.value
        XCTAssertEqual(model.rows.first?.id, DashboardPreviewData.rows[1].id)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderFailureCannotClearNewerPagingState() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        let old = Task { await model.refreshData() }
        await loader.waitForRequest(1)
        let latest = Task { await model.refreshData(mode: .paging) }
        await loader.waitForRequest(2)
        await loader.finish(1, with: .failure(URLError(.timedOut)))
        await old.value
        XCTAssertTrue(model.isPaging)
        XCTAssertNil(model.errorMessage)
        await loader.finish(2, with: .success(page(1)))
        await latest.value
        XCTAssertFalse(model.isPaging)
    }

    func testCancelledTableQueryCannotPublishEvenWhenLoaderIgnoresCancellation() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        let task = Task { await model.refreshData() }
        await loader.waitForRequest(1)
        task.cancel()
        await loader.finish(1, with: .success(page(0)))
        await task.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testSearchInvalidatesRunningQueryBeforeDebounceCompletes() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        let old = Task { await model.refreshData() }
        await loader.waitForRequest(1)
        model.searchText = "new search"
        model.onSearchTextChanged()
        await loader.finish(1, with: .success(page(0)))
        await old.value
        XCTAssertTrue(model.rows.isEmpty)
        // 筛选立即刷新会替代尚未执行的搜索防抖。
        model.onFiltersChanged()
        await loader.waitForRequest(2)
        await loader.finish(2, with: .success(page(1)))
        // reset 取消模型持有的任务，避免测试间遗留工作。
        model.resetForAccountSwitch()
    }

    func testChangedPageRejectsResultBeforeReplacementStarts() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        let task = Task { await model.refreshData() }
        await loader.waitForRequest(1)
        model.currentPage = 2
        await loader.finish(1, with: .success(page(0)))
        await task.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.currentPage, 2)
    }

    func testRetryOnDatabasePublishesResult() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        model.errorMessage = "previous failure"
        model.retryAfterError()
        await loader.waitForRequest(1)
        await loader.finish(1, with: .success(page(0)))
        // 等模型拥有的任务提交结果，再检查重试状态。
        for _ in 0..<100 where model.isLoading { await Task.yield() }
        XCTAssertEqual(model.rows.first?.id, DashboardPreviewData.rows[0].id)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testEmptyRetryBootstrapDoesNotCancelItsOwnRefresh() async throws {
        let loader = ControlledDashboardLoader<DashboardPageResult>()
        let model = try makeModel(pages: loader)
        model.dataSource = .empty
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting()) {
            model.bootstrapDataSource(hasMetrics: true)
            await model.refreshData()
        }
        model.retryAfterError()
        await loader.waitForRequest(1)
        await loader.finish(1, with: .success(page(0)))
        for _ in 0..<100 where model.isLoading { await Task.yield() }
        XCTAssertEqual(model.rows.first?.id, DashboardPreviewData.rows[0].id)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderChartSuccessCannotReplaceNewerSnapshot() async throws {
        let loader = ControlledDashboardLoader<DataDashboardSnapshot>()
        let model = try makeModel(charts: loader)
        let old = Task { await model.refreshDataDashboard() }
        await loader.waitForRequest(1)
        let latest = Task { await model.refreshDataDashboard() }
        await loader.waitForRequest(2)
        var latestSnapshot = DataDashboardSnapshot.empty
        latestSnapshot.reportingPeriodLabel = "latest"
        await loader.finish(2, with: .success(latestSnapshot))
        await latest.value
        await loader.finish(1, with: .success(.empty))
        await old.value
        XCTAssertEqual(model.dataDashboardSnapshot.reportingPeriodLabel, "latest")
        XCTAssertFalse(model.isLoadingDataDashboard)
    }

    func testOlderChartFailureCannotClearLatestLoadingState() async throws {
        let loader = ControlledDashboardLoader<DataDashboardSnapshot>()
        let model = try makeModel(charts: loader)
        let old = Task { await model.refreshDataDashboard() }
        await loader.waitForRequest(1)
        let latest = Task { await model.refreshDataDashboard() }
        await loader.waitForRequest(2)
        await loader.finish(1, with: .failure(URLError(.timedOut)))
        await old.value
        XCTAssertTrue(model.isLoadingDataDashboard)
        XCTAssertNil(model.dataDashboardErrorMessage)
        await loader.finish(2, with: .success(.empty))
        await latest.value
        XCTAssertFalse(model.isLoadingDataDashboard)
    }

    func testCancelledChartFailureIsNotDisplayed() async throws {
        let loader = ControlledDashboardLoader<DataDashboardSnapshot>()
        let model = try makeModel(charts: loader)
        let task = Task { await model.refreshDataDashboard() }
        await loader.waitForRequest(1)
        task.cancel()
        await loader.finish(1, with: .failure(URLError(.timedOut)))
        await task.value
        XCTAssertNil(model.dataDashboardErrorMessage)
        XCTAssertFalse(model.isLoadingDataDashboard)
    }
}

/// 故意忽略取消，让测试能够精确控制旧/新查询的返回次序。
private actor ControlledDashboardLoader<Value: Sendable> {
    private var requestCount = 0
    private var pending: [Int: CheckedContinuation<Value, Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func load() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            requestCount += 1
            pending[requestCount] = continuation
            let ready = observers.filter { $0.0 <= requestCount }
            observers.removeAll { $0.0 <= requestCount }
            for (_, observer) in ready { observer.resume() }
        }
    }

    func waitForRequest(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func finish(_ request: Int, with result: Result<Value, Error>) {
        pending.removeValue(forKey: request)?.resume(with: result)
    }
}
