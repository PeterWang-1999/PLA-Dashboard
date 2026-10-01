import XCTest
@testable import PLADashboard

final class DashboardPageLoadPerformanceTests: XCTestCase {
    /// 查询、周指标读取及行转换；不包含 SwiftUI 渲染、图片或搜索防抖。
    func testPageLoadBaseline() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 40_000, merchantRows: 2_000)
        let scenarios: [(String, DashboardQueryFilters, Int)] = [
            ("first", DashboardQueryFilters(), 1),
            ("paging", DashboardQueryFilters(), 30),
            ("label", DashboardQueryFilters(customLabelFilter: .value(column: "自定义标签 0", value: "EN")), 1),
            ("roi_sort", DashboardQueryFilters(sort: .roiDescending), 1),
            ("search", DashboardQueryFilters(searchText: "00000001"), 1)
        ]
        var report = "PAGE_LOAD samples=11 products=2000 facts=40000 inMemory=true\n"
        for (name, filters, page) in scenarios {
            var samples: [Double] = []
            let expected = try await client.fetchDashboardPage(filters: filters, page: page, pageSize: 30)
            for index in 0..<12 {
                let start = CFAbsoluteTimeGetCurrent()
                let result = try await client.fetchDashboardPage(filters: filters, page: page, pageSize: 30)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                XCTAssertEqual(result.rows, expected.rows)
                XCTAssertEqual(result.totalCount, expected.totalCount)
                if index > 0 { samples.append(elapsed) }
            }
            samples.sort()
            report += "\(name) p50_ms=\(samples[5]) p95_ms=\(samples[10]) count=\(expected.totalCount)\n"
        }
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "dashboard-page-load"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPaginationMatchesUnboundedQueryForEverySort() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 800, merchantRows: 40)
        for sort in DashboardTableSort.allCases {
            let filters = DashboardQueryFilters(sort: sort)
            let all = try await client.fetchDashboardAllRows(filters: filters)
            var paged: [ProductPerformanceRowModel] = []
            for page in 1...6 {
                let result = try await client.fetchDashboardPage(filters: filters, page: page, pageSize: 7)
                XCTAssertEqual(result.totalCount, all.totalCount)
                XCTAssertEqual(result.totalPages, 6)
                paged += result.rows
            }
            XCTAssertEqual(paged, all.rows)
        }
        let empty = try await client.fetchDashboardPage(
            filters: DashboardQueryFilters(searchText: "not-a-product"), page: 1, pageSize: 7
        )
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertEqual(empty.totalCount, 0)
        XCTAssertEqual(empty.totalPages, 1)
    }
    func testCountRefreshesAfterAnotherConnectionImportsProducts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("count.sqlite")
        let reader = try DatabaseClient.make(at: databaseURL, accountID: "count-test")
        let writer = try DatabaseClient.make(at: databaseURL, accountID: "count-test")
        let merchantURL = directory.appendingPathComponent("merchant.tsv")
        let adsURL = directory.appendingPathComponent("ads.csv")
        let merchant = BenchmarkTestSupport.makeMerchantTSV(rowCount: 40)
        try merchant.write(to: merchantURL, atomically: true, encoding: .utf8)
        try BenchmarkTestSupport.makeAdsCSV(rowCount: 800).write(to: adsURL, atomically: true, encoding: .utf8)
        _ = try await MerchantCenterImporter(databaseClient: writer).importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: writer).importFile(sourceURL: adsURL) { _ in }
        try await writer.rebuildProductWeeklyMetrics()
        let filters = DashboardQueryFilters(customLabelFilter: .value(column: "自定义标签 0", value: "EN"))
        let before = try await reader.fetchDashboardPage(filters: filters, page: 1, pageSize: 7)
        XCTAssertEqual(before.totalCount, 40)
        try BenchmarkTestSupport.makeMerchantTSV(rowCount: 80).write(to: merchantURL, atomically: true, encoding: .utf8)
        try BenchmarkTestSupport.makeAdsCSV(rowCount: 1600).write(to: adsURL, atomically: true, encoding: .utf8)
        _ = try await MerchantCenterImporter(databaseClient: writer).importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: writer).importFile(sourceURL: adsURL) { _ in }
        try await writer.rebuildProductWeeklyMetrics()
        let after = try await reader.fetchDashboardPage(filters: filters, page: 1, pageSize: 7)
        XCTAssertEqual(after.totalCount, 80)
        XCTAssertEqual(after.totalPages, 12)
        let full = try await reader.fetchDashboardAllRows(filters: filters)
        XCTAssertEqual(after.rows, Array(full.rows.prefix(7)))
    }

}
