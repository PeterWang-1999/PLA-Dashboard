import XCTest
import GRDB
@testable import PLADashboard

/// 针对本机沙盒生产库的预警标签验算（需 `PLA_VERIFY_PRODUCTION=1`）。
final class ProductionWarningLabelVerificationTests: XCTestCase {
    private struct ProductProbe: Sendable {
        let query: String
        let normalizedProductID: String
    }

    private let probes: [ProductProbe] = [
        ProductProbe(query: "S10508123", normalizedProductID: "10508123"),
        ProductProbe(query: "S13390585", normalizedProductID: "13390585"),
        ProductProbe(query: "10377544106259", normalizedProductID: "10377544106259"),
    ]

    func testVerifyWarningLabelsInProductionDatabase() async throws {
        let shouldRun = ProcessInfo.processInfo.environment["PLA_VERIFY_PRODUCTION"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/pla_verify_production")
        guard shouldRun else {
            throw XCTSkip("Set PLA_VERIFY_PRODUCTION=1 or touch /tmp/pla_verify_production.")
        }

        let databaseClient = try DatabaseClient.make()
        try await databaseClient.migrateIfNeeded()

        let latestDay = try await databaseClient.fetchLatestMetricDay()
        let endDate = try XCTUnwrap(latestDay.flatMap(WeekCalendar.parseDay(_:)), "No ads_product_daily data")
        let weekStarts = WeekCalendar.reportingWeekStarts(endingAt: endDate)
        XCTAssertEqual(weekStarts.count, AnalyticsConfiguration.reportingWeekCount)

        let overallWeeks = try await databaseClient.fetchOverallWeeklyMetrics(weekStarts: weekStarts)
        let cohortBenchmarks = try await databaseClient.fetchWeeklyCohortSpendBenchmarks(weekStarts: weekStarts)
        let overallBenchmark = overallWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
        let totalCostCents = overallBenchmark.costCents

        print("\n=== Report window ===")
        print("latestDay=\(latestDay ?? "nil") weeks=\(weekStarts.joined(separator: ", "))")
        print("portfolio6wCostCents=\(totalCostCents) overallWeightedROI=\(WeeklyMetricsRules.weightedROI(weeklyMetrics: overallWeeks.map(\.metrics)))")

        for probe in probes {
            print("\n=== Product probe: \(probe.query) → product_id \(probe.normalizedProductID) ===")

            if let productRow = try await databaseClient.lookupProduct(
                productId: probe.normalizedProductID,
                lsin: probe.query
            ) {
                print("products: id=\(productRow.productId) lsin=\(productRow.lsin ?? "nil") title=\(productRow.title ?? "nil")")
            } else {
                print("products: NOT FOUND by product_id or lsin")
            }

            let weeklyRecords = try await databaseClient.fetchWeeklyMetrics(
                productIds: [probe.normalizedProductID],
                weekStarts: weekStarts
            )
            let recordByWeek = Dictionary(uniqueKeysWithValues: weeklyRecords.map { ($0.weekStart, $0) })
            let productWeeks: [WeeklyProductMetrics] = weekStarts.map { week in
                let metrics = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
                return WeeklyProductMetrics(
                    productId: probe.normalizedProductID,
                    weekStart: week,
                    metrics: metrics
                )
            }

            let sixWeekTotals = productWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
            print("6w totals: cost=\(sixWeekTotals.costCents)c (\(DashboardMetricFormatter.formatCurrencyFromCents(sixWeekTotals.costCents))) share=\(DashboardMetricFormatter.formatSharePercent(costCents: sixWeekTotals.costCents, totalCostCents: totalCostCents)) roi=\(DashboardMetricFormatter.formatDecimal(sixWeekTotals.roi)) clicks=\(sixWeekTotals.clicks) conv=\(sixWeekTotals.conversions)")

            for week in weekStarts {
                let m = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
                let cohort = cohortBenchmarks.first { $0.weekStart == week }
                let overall = overallWeeks.first { $0.weekStart == week }?.metrics ?? AggregatedMetrics()
                let daily = Double(m.costCents) / 7.0
                let median = cohort?.medianDailyCents ?? 0
                let mean = cohort?.meanDailyCents ?? 0
                let lowThreshold = WeeklyMetricsRules.lowSpendDailyThreshold(medianDailyCents: median)
                let highThreshold = AnalyticsConfiguration.highSpendMeanRatio * mean
                print("  week \(week): cost=\(m.costCents)c daily=\(String(format: "%.2f", daily)) roi=\(String(format: "%.2f", m.roi)) overallROI=\(String(format: "%.2f", overall.roi)) cohortMed=\(String(format: "%.2f", median)) cohortMean=\(String(format: "%.2f", mean)) lowTh=\(String(format: "%.2f", lowThreshold)) highTh=\(String(format: "%.2f", highThreshold))")
            }

            let productWeightedROI = WeeklyMetricsRules.weightedROI(weeklyMetrics: productWeeks.map(\.metrics))
            let overallWeightedROI = WeeklyMetricsRules.weightedROI(weeklyMetrics: overallWeeks.map(\.metrics))
            let recentWeeks = Array(weekStarts.suffix(AnalyticsConfiguration.consumptionLookbackWeeks))
            let underperformWeeks = recentWeeks.filter { week in
                let productROI = recordByWeek[week]?.aggregatedMetrics.roi ?? 0
                let overallROI = overallWeeks.first { $0.weekStart == week }?.metrics.roi ?? 0
                return productROI < overallROI
            }
            print("weightedROI product=\(String(format: "%.4f", productWeightedROI)) overall=\(String(format: "%.4f", overallWeightedROI)) recentUnderperformWeeks=\(underperformWeeks)")

            let warning = WeeklyMetricsRules.resolveWarningLabel(
                productWeeks: productWeeks,
                overallWeeks: overallWeeks,
                cohortBenchmarks: cohortBenchmarks,
                totalPortfolioCostCents: totalCostCents
            )
            print("resolvedWarningLabel=\(warning?.rawValue ?? "—")")
        }

        print("\n=== Latest ads import ===")
        print(try await databaseClient.latestAdsImportSummary())

        var report = ""
        func append(_ line: String) { report += line + "\n" }
        append("latestDay=\(latestDay ?? "nil")")
        append("weeks=\(weekStarts.joined(separator: ", "))")
        append("portfolio6wCostCents=\(totalCostCents)")
        for probe in probes {
            let weeklyRecords = try await databaseClient.fetchWeeklyMetrics(
                productIds: [probe.normalizedProductID],
                weekStarts: weekStarts
            )
            let recordByWeek = Dictionary(uniqueKeysWithValues: weeklyRecords.map { ($0.weekStart, $0) })
            let productWeeks: [WeeklyProductMetrics] = weekStarts.map { week in
                let metrics = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
                return WeeklyProductMetrics(productId: probe.normalizedProductID, weekStart: week, metrics: metrics)
            }
            let sixWeekTotals = productWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
            let warning = WeeklyMetricsRules.resolveWarningLabel(
                productWeeks: productWeeks,
                overallWeeks: overallWeeks,
                cohortBenchmarks: cohortBenchmarks,
                totalPortfolioCostCents: totalCostCents
            )
            append("--- \(probe.query) / \(probe.normalizedProductID) ---")
            append("6w costCents=\(sixWeekTotals.costCents) roi=\(sixWeekTotals.roi) clicks=\(sixWeekTotals.clicks) conv=\(sixWeekTotals.conversions)")
            append("warning=\(warning?.rawValue ?? "—")")
            let daily = try await databaseClient.adsDailyTotals(productId: probe.normalizedProductID)
            append("ads_daily deduped all-time: rows=\(daily.rowCount) costCents=\(daily.costCents) clicks=\(daily.clicks) conv=\(daily.conversions) cvCents=\(daily.conversionValueCents)")
            for week in weekStarts {
                let m = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
                append("  \(week): costCents=\(m.costCents) roi=\(m.roi)")
            }
        }
        append(try await databaseClient.latestAdsImportSummary())
        let attachment = XCTAttachment(string: report)
        attachment.name = "warning-label-verify-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct ProductLookupRow: Sendable {
    let productId: String
    let lsin: String?
    let title: String?
}

private extension DatabaseClient {
    func lookupProduct(productId: String, lsin: String) async throws -> ProductLookupRow? {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT product_id, lsin, title
                    FROM products
                    WHERE product_id = ?
                       OR lsin = ?
                    LIMIT 1;
                    """,
                arguments: [productId, lsin]
            )
            guard let row else { return nil }
            return ProductLookupRow(
                productId: row["product_id"],
                lsin: row["lsin"],
                title: row["title"]
            )
        }
    }

    func latestAdsImportSummary() async throws -> String {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT id, source_kind, file_name, status, imported_at, valid_rows, total_rows
                FROM import_jobs
                WHERE source_kind = ?
                ORDER BY imported_at DESC
                LIMIT 1;
                """, arguments: [ImportSourceKind.adsProduct.rawValue])
            guard let row else { return "no ads import_jobs row" }
            return "id=\(row["id"] ?? "") file=\(row["file_name"] ?? "") status=\(row["status"] ?? "") valid=\(row["valid_rows"] ?? 0)/\(row["total_rows"] ?? 0) at=\(row["imported_at"] ?? "")"
        }
    }

    func adsDailyTotals(productId: String) async throws -> (rowCount: Int, costCents: Int, clicks: Int, conversions: Double, conversionValueCents: Int) {
        try await dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                WITH ranked AS (
                  SELECT a.cost_micros, a.clicks, a.conversions, a.conversion_value_cents,
                    ROW_NUMBER() OVER (
                      PARTITION BY a.date, a.item_id, a.campaign, a.currency_code
                      ORDER BY j.imported_at DESC
                    ) AS rn
                  FROM ads_product_daily a
                  INNER JOIN import_jobs j ON j.id = a.import_id
                  WHERE j.status = ? AND a.product_id = ?
                )
                SELECT COUNT(*) AS row_count,
                       COALESCE(SUM(cost_micros) / 10000, 0) AS cost_cents,
                       COALESCE(SUM(clicks), 0) AS clicks,
                       COALESCE(SUM(conversions), 0) AS conversions,
                       COALESCE(SUM(conversion_value_cents), 0) AS conversion_value_cents
                FROM ranked WHERE rn = 1;
                """, arguments: [ImportJobStatus.succeeded.rawValue, productId])
            return (
                row?["row_count"] ?? 0,
                row?["cost_cents"] ?? 0,
                row?["clicks"] ?? 0,
                row?["conversions"] ?? 0.0,
                row?["conversion_value_cents"] ?? 0
            )
        }
    }
}
