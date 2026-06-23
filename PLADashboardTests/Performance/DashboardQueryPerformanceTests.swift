import XCTest
@testable import PLADashboard

final class DashboardQueryPerformanceTests: XCTestCase {
    private var databaseClient: DatabaseClient!

    override func setUp() async throws {
        try await super.setUp()
        databaseClient = try await BenchmarkTestSupport.seedBenchmarkDatabase(
            adsRows: BenchmarkConfiguration.performanceTestAdsRowCount,
            merchantRows: 500
        )
    }

    func testFetchDashboardPageMeasure() async throws {
        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            group.enter()
            Task {
                do {
                    _ = try await self.databaseClient.fetchDashboardPage(
                        filters: DashboardQueryFilters(),
                        page: 1,
                        pageSize: 30
                    )
                } catch {
                    XCTFail("\(error)")
                }
                group.leave()
            }
            group.wait()
        }
    }

    func testSearchProductIDsMeasure() async throws {
        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            group.enter()
            Task {
                do {
                    _ = try await self.databaseClient.searchProductIDs(query: "00000001", limit: 500)
                } catch {
                    XCTFail("\(error)")
                }
                group.leave()
            }
            group.wait()
        }
    }

    func testDashboardPageReturnsOnlyPageSizeRows() async throws {
        let result = try await databaseClient.fetchDashboardPage(
            filters: DashboardQueryFilters(),
            page: 1,
            pageSize: 30
        )
        XCTAssertLessThanOrEqual(result.rows.count, 30)
        XCTAssertGreaterThan(result.totalCount, 30)
    }

    func testDashboardQueryWithinSLA() async throws {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try await databaseClient.fetchDashboardPage(
            filters: DashboardQueryFilters(),
            page: 1,
            pageSize: 30
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(
            elapsed,
            BenchmarkConfiguration.dashboardQuerySLASeconds,
            "看板首屏查询应 < \(BenchmarkConfiguration.dashboardQuerySLASeconds)s，实测 \(elapsed)s"
        )
    }
}
