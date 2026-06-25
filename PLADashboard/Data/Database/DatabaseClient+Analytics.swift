import Foundation
import GRDB

extension DatabaseClient {
    func hasFactTableData() throws -> Bool {
        try dbQueue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM ads_product_daily;
                """) ?? 0
            return count > 0
        }
    }

    func fetchLatestMetricDay() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT MAX(date) FROM ads_product_daily;
                """)
        }
    }

    func rebuildProductWeeklyMetrics() throws {
        let signpost = PerformanceSignposts.beginETLRebuild()
        defer { PerformanceSignposts.endETLRebuild(signpost) }

        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM product_weekly_metrics;")
            try db.execute(sql: """
                INSERT INTO product_weekly_metrics (
                  product_id,
                  week_start,
                  cost_cents,
                  impressions,
                  clicks,
                  conversions,
                  conversion_value_cents,
                  gross_sales_cents,
                  roi,
                  cpa_cents,
                  cpc_cents,
                  cvr,
                  aos,
                  warning_label
                )
                SELECT
                  product_id,
                  week_start,
                  cost_cents,
                  impressions,
                  clicks,
                  conversions,
                  conversion_value_cents,
                  0 AS gross_sales_cents,
                  CASE
                    WHEN cost_cents > 0
                    THEN CAST(conversion_value_cents AS REAL) / CAST(cost_cents AS REAL)
                    ELSE NULL
                  END AS roi,
                  CASE
                    WHEN conversions > 0
                    THEN CAST(ROUND(CAST(cost_cents AS REAL) / conversions) AS INTEGER)
                    ELSE NULL
                  END AS cpa_cents,
                  CASE
                    WHEN clicks > 0 THEN cost_cents / clicks
                    ELSE NULL
                  END AS cpc_cents,
                  CASE
                    WHEN clicks > 0 THEN conversions / CAST(clicks AS REAL)
                    ELSE NULL
                  END AS cvr,
                  CASE
                    WHEN conversions > 0
                    THEN CAST(conversion_value_cents AS REAL) / conversions / 100.0
                    ELSE NULL
                  END AS aos,
                  NULL AS warning_label
                FROM (
                  SELECT
                    product_id,
                    date(date, '-' || CAST(strftime('%w', date) AS INTEGER) || ' days') AS week_start,
                    SUM(cost_micros) / 10000 AS cost_cents,
                    SUM(impressions) AS impressions,
                    SUM(clicks) AS clicks,
                    SUM(conversions) AS conversions,
                    SUM(conversion_value_cents) AS conversion_value_cents
                  FROM (
                    WITH ranked AS (
                      SELECT
                        a.product_id,
                        a.date,
                        a.cost_micros,
                        a.impressions,
                        a.clicks,
                        a.conversions,
                        a.conversion_value_cents,
                        ROW_NUMBER() OVER (
                          PARTITION BY a.date, a.item_id, a.campaign, a.currency_code
                          ORDER BY j.imported_at DESC
                        ) AS rn
                      FROM ads_product_daily a
                      INNER JOIN import_jobs j ON j.id = a.import_id
                      WHERE j.status = ?
                    )
                    SELECT
                      product_id,
                      date,
                      cost_micros,
                      impressions,
                      clicks,
                      conversions,
                      conversion_value_cents
                    FROM ranked
                    WHERE rn = 1
                  ) AS deduped_daily
                  GROUP BY product_id, week_start
                ) AS weekly_rollup;
                """, arguments: [ImportJobStatus.succeeded.rawValue])
        }
        invalidateDashboardCache()
    }

    func fetchWeeklyMetrics(
        productIds: [String],
        weekStarts: [String]
    ) throws -> [ProductWeeklyMetricsRecord] {
        guard !productIds.isEmpty, !weekStarts.isEmpty else { return [] }
        return try dbQueue.read { db in
            let idPlaceholders = Array(repeating: "?", count: productIds.count).joined(separator: ", ")
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            let sql = """
                SELECT *
                FROM product_weekly_metrics
                WHERE product_id IN (\(idPlaceholders))
                  AND week_start IN (\(weekPlaceholders));
                """
            var arguments = StatementArguments()
            for id in productIds { arguments += [id] }
            for week in weekStarts { arguments += [week] }
            return try ProductWeeklyMetricsRecord.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    func fetchWeeklyCohortSpendBenchmarks(weekStarts: [String]) throws -> [WeeklyCohortSpendBenchmark] {
        guard !weekStarts.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            let sql = """
                SELECT week_start, cost_cents
                FROM product_weekly_metrics
                WHERE week_start IN (\(placeholders))
                  AND cost_cents > 0
                ORDER BY week_start ASC, cost_cents ASC;
                """
            var arguments = StatementArguments()
            for week in weekStarts { arguments += [week] }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            var costsByWeek: [String: [Int]] = [:]
            for row in rows {
                guard let weekStart: String = row["week_start"] else { continue }
                let costCents: Int = row["cost_cents"] ?? 0
                costsByWeek[weekStart, default: []].append(costCents)
            }

            return weekStarts.map { weekStart in
                let benchmark = WeeklyMetricsRules.cohortBenchmark(
                    fromActiveProductWeeklyCostCents: costsByWeek[weekStart] ?? []
                )
                return WeeklyCohortSpendBenchmark(
                    weekStart: weekStart,
                    medianDailyCents: benchmark.medianDaily,
                    meanDailyCents: benchmark.meanDaily
                )
            }
        }
    }

    func fetchOverallWeeklyMetrics(weekStarts: [String]) throws -> [WeeklyProductMetrics] {
        guard !weekStarts.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            let sql = """
                SELECT week_start,
                       SUM(cost_cents) AS cost_cents,
                       SUM(impressions) AS impressions,
                       SUM(clicks) AS clicks,
                       SUM(conversions) AS conversions,
                       SUM(conversion_value_cents) AS conversion_value_cents,
                       SUM(gross_sales_cents) AS gross_sales_cents
                FROM product_weekly_metrics
                WHERE week_start IN (\(placeholders))
                GROUP BY week_start
                ORDER BY week_start ASC;
                """
            var arguments = StatementArguments()
            for week in weekStarts { arguments += [week] }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap { row in
                guard let weekStart: String = row["week_start"] else { return nil }
                let metrics = AggregatedMetrics(
                    costCents: row["cost_cents"] ?? 0,
                    impressions: row["impressions"] ?? 0,
                    clicks: row["clicks"] ?? 0,
                    conversions: row["conversions"] ?? 0,
                    conversionValueCents: row["conversion_value_cents"] ?? 0,
                    grossSalesCents: row["gross_sales_cents"] ?? 0
                )
                return WeeklyProductMetrics(productId: "__overall__", weekStart: weekStart, metrics: metrics)
            }
        }
    }

    func countExpiredAdsDailyRows(retentionDays: Int) throws -> Int {
        guard retentionDays > 0, let cutoff = retentionCutoffDay(retentionDays: retentionDays) else {
            return 0
        }
        return try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ads_product_daily WHERE date < ?;",
                arguments: [cutoff]
            ) ?? 0
        }
    }

    @discardableResult
    func purgeExpiredAdsDaily(retentionDays: Int) throws -> Int {
        guard retentionDays > 0, let cutoff = retentionCutoffDay(retentionDays: retentionDays) else {
            return 0
        }
        let deleted = try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM ads_product_daily WHERE date < ?;",
                arguments: [cutoff]
            )
            return db.changesCount
        }
        if deleted > 0 {
            try rebuildProductWeeklyMetrics()
        } else {
            invalidateDashboardCache()
        }
        return deleted
    }

    func runScheduledRetentionPurgeIfNeeded() throws {
        let retentionDays = AppSettings.dataRetentionDays(accountID: accountID)
        guard retentionDays > 0 else { return }

        guard let latestDay = try fetchLatestMetricDay() else { return }
        if AppSettings.lastRetentionPurgeDay(accountID: accountID) == latestDay {
            return
        }

        let deleted = try purgeExpiredAdsDaily(retentionDays: retentionDays)
        if deleted >= 0 {
            AppSettings.setLastRetentionPurgeDay(latestDay, accountID: accountID)
        }
    }

    private func retentionCutoffDay(retentionDays: Int) -> String? {
        guard retentionDays > 0 else { return nil }
        guard let latestDay = try? fetchLatestMetricDay(),
              let anchor = WeekCalendar.parseDay(latestDay) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: anchor) else {
            return nil
        }
        return WeekCalendar.formatDay(cutoffDate)
    }
}
