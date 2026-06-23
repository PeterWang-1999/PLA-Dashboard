import GRDB
import XCTest
@testable import PLADashboard

final class QueryPlanTests: XCTestCase {
    func testDashboardRankedQueryUsesIndexOnWeeklyMetrics() async throws {
        let databaseClient = try await BenchmarkTestSupport.seedBenchmarkDatabase(
            adsRows: 200,
            merchantRows: 20
        )

        let weekStarts = ["2026-06-01", "2026-06-08", "2026-06-15"]
        let placeholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
        let sql = """
            SELECT p.product_id
            FROM products p
            INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
            WHERE m.week_start IN (\(placeholders))
            GROUP BY p.product_id
            HAVING SUM(m.cost_cents) > 0
            ORDER BY SUM(m.cost_cents) DESC
            LIMIT 30;
            """
        var arguments = StatementArguments()
        for week in weekStarts { arguments += [week] }

        let plan = try await databaseClient.explainQueryPlan(sql: sql, arguments: arguments)
        let joined = plan.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            joined.contains("product_weekly_metrics") || joined.contains("using index"),
            "查询计划应引用 product_weekly_metrics 或索引：\(plan)"
        )
        XCTAssertFalse(
            joined.contains("scan table products"),
            "不应全表扫描 products：\(plan)"
        )
    }

    func testFTSSearchUsesProductSearchVirtualTable() async throws {
        let databaseClient = try await BenchmarkTestSupport.seedBenchmarkDatabase(
            adsRows: 50,
            merchantRows: 5
        )

        let plan = try await databaseClient.explainQueryPlan(
            sql: """
                SELECT product_id FROM product_search WHERE product_search MATCH ? LIMIT 10;
                """,
            arguments: ["\"EN\"*"]
        )
        let joined = plan.joined(separator: "\n").lowercased()
        XCTAssertTrue(joined.contains("product_search"), "FTS 应扫描 product_search：\(plan)")
    }
}
