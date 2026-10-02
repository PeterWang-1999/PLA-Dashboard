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
        try rebuildProductWeeklyMetrics(incremental: false)
    }

    /// 成功导入后仅重算持久失效集合；未建立完整基线时自动全量恢复。
    func refreshProductWeeklyMetricsAfterImport() throws {
        try rebuildProductWeeklyMetrics(incremental: true)
    }

    private func rebuildProductWeeklyMetrics(incremental: Bool) throws {
        try Task.checkCancellation()
        let signpost = PerformanceSignposts.beginETLRebuild()
        defer { PerformanceSignposts.endETLRebuild(signpost) }

        let didRefresh = try dbQueue.write { db -> Bool in
            let hasRefreshState = try db.tableExists("weekly_metrics_refresh_state")
            let initialized = hasRefreshState
                ? (try Int.fetchOne(db, sql: "SELECT initialized FROM weekly_metrics_refresh_state WHERE id = 1;") ?? 0) == 1
                : false
            let pendingCount = incremental && initialized
                ? (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM weekly_metrics_dirty_products;") ?? 0)
                : 0
            if incremental && initialized && pendingCount == 0 { return false }
            let existingProducts = incremental && initialized
                ? (try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT product_id) FROM product_weekly_metrics;") ?? 0)
                : 0
            // 覆盖大部分产品时保留全量路径，避免准备键集的额外开销。
            let scoped = incremental && initialized && pendingCount * 2 < existingProducts
            if scoped {
                try prepareWeeklyMetricsRefreshKeys(db)
                try db.execute(sql: "DELETE FROM product_weekly_metrics WHERE product_id IN (SELECT product_id FROM weekly_metrics_dirty_products);")
            } else {
                try db.execute(sql: "DELETE FROM product_weekly_metrics;")
            }
            try Task.checkCancellation()
            let adsSource = scoped ? "temp.weekly_metrics_ads_keys k CROSS JOIN ads_product_daily a ON k.date = a.date AND k.item_id = a.item_id AND k.campaign = a.campaign AND k.currency_code = a.currency_code" : "ads_product_daily a"
            let salesSource = scoped ? "temp.weekly_metrics_sales_keys k CROSS JOIN sales_daily s ON k.date = s.date AND k.lsin = s.lsin" : "sales_daily s"
            let productScope = scoped ? "AND product_id IN (SELECT product_id FROM weekly_metrics_dirty_products)" : ""
            // 键集 = 有投放的产品 ×（该产品有投放或有销售的周）。
            // 不能只用投放周 LEFT JOIN 销售：无花费但有 GS 的周必须保留，
            // 否则加权毛利/近 3 周活跃会丢数（对标 Python 产品×周完整网格）。
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
                  gross_profit_cents,
                  roi,
                  cpa_cents,
                  cpc_cents,
                  cvr,
                  aos
                )
                WITH ads_weekly AS (
                  SELECT
                    product_id,
                    date(date, '-' || CAST(strftime('%w', date) AS INTEGER) || ' days') AS week_start,
                    SUM(cost_micros) / 10000 AS cost_cents,
                    SUM(impressions) AS impressions,
                    SUM(clicks) AS clicks,
                    SUM(conversions) AS conversions,
                    SUM(conversion_value_cents) AS conversion_value_cents
                  FROM (
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
                        ORDER BY j.imported_at DESC, a.rowid DESC
                      ) AS rn
                    FROM \(adsSource)
                    INNER JOIN import_jobs j ON j.id = a.import_id
                    WHERE j.status = ?
                  ) AS ranked_ads
                  WHERE rn = 1 \(productScope)
                  GROUP BY product_id, week_start
                ),
                sales_weekly AS (
                  SELECT
                    product_id,
                    date(date, '-' || CAST(strftime('%w', date) AS INTEGER) || ' days') AS week_start,
                    SUM(gross_sales_cents) AS gross_sales_cents,
                    SUM(gross_profit_cents) AS gross_profit_cents
                  FROM (
                    SELECT
                      s.product_id,
                      s.date,
                      s.gross_sales_cents,
                      s.gross_profit_cents,
                      ROW_NUMBER() OVER (
                        PARTITION BY s.date, s.lsin
                        ORDER BY j.imported_at DESC, s.rowid DESC
                      ) AS rn
                    FROM \(salesSource)
                    INNER JOIN import_jobs j ON j.id = s.import_id
                    WHERE j.status = ?
                      AND s.product_id IS NOT NULL
                      AND TRIM(s.product_id) != ''
                  ) AS ranked_sales
                  WHERE rn = 1 \(productScope)
                  GROUP BY product_id, week_start
                ),
                week_keys AS (
                  SELECT product_id, week_start FROM ads_weekly
                  UNION
                  SELECT s.product_id, s.week_start
                  FROM sales_weekly s
                  WHERE s.product_id IN (SELECT DISTINCT product_id FROM ads_weekly)
                )
                SELECT
                  k.product_id,
                  k.week_start,
                  COALESCE(a.cost_cents, 0) AS cost_cents,
                  COALESCE(a.impressions, 0) AS impressions,
                  COALESCE(a.clicks, 0) AS clicks,
                  COALESCE(a.conversions, 0) AS conversions,
                  COALESCE(a.conversion_value_cents, 0) AS conversion_value_cents,
                  COALESCE(s.gross_sales_cents, 0) AS gross_sales_cents,
                  COALESCE(s.gross_profit_cents, 0) AS gross_profit_cents,
                  CASE
                    WHEN COALESCE(a.cost_cents, 0) > 0
                    THEN CAST(COALESCE(a.conversion_value_cents, 0) AS REAL)
                         / CAST(a.cost_cents AS REAL)
                    ELSE NULL
                  END AS roi,
                  CASE
                    WHEN COALESCE(a.conversions, 0) > 0
                    THEN CAST(ROUND(
                      CAST(COALESCE(a.cost_cents, 0) AS REAL) / a.conversions
                    ) AS INTEGER)
                    ELSE NULL
                  END AS cpa_cents,
                  CASE
                    WHEN COALESCE(a.clicks, 0) > 0
                    THEN COALESCE(a.cost_cents, 0) / a.clicks
                    ELSE NULL
                  END AS cpc_cents,
                  CASE
                    WHEN COALESCE(a.clicks, 0) > 0
                    THEN COALESCE(a.conversions, 0) / CAST(a.clicks AS REAL)
                    ELSE NULL
                  END AS cvr,
                  CASE
                    WHEN COALESCE(a.conversions, 0) > 0
                    THEN CAST(COALESCE(a.conversion_value_cents, 0) AS REAL)
                         / a.conversions / 100.0
                    ELSE NULL
                  END AS aos
                FROM week_keys k
                LEFT JOIN ads_weekly a
                  ON a.product_id = k.product_id
                 AND a.week_start = k.week_start
                LEFT JOIN sales_weekly s
                  ON s.product_id = k.product_id
                 AND s.week_start = k.week_start;
                """, arguments: [
                ImportJobStatus.succeeded.rawValue,
                ImportJobStatus.succeeded.rawValue,
            ])
            try Task.checkCancellation()
            if hasRefreshState {
                try db.execute(sql: "DELETE FROM weekly_metrics_dirty_products;")
                try db.execute(sql: "UPDATE weekly_metrics_refresh_state SET initialized = 1 WHERE id = 1;")
            }
            return true
        }
        if didRefresh { invalidateDashboardCache() }
    }

    private func prepareWeeklyMetricsRefreshKeys(_ db: Database) throws {
        // 先收集自然键，再读键下的所有候选，避免先按产品过滤而选错最新覆盖记录。
        try db.execute(sql: """
            CREATE TEMP TABLE IF NOT EXISTS weekly_metrics_ads_keys (
              date TEXT, item_id TEXT, campaign TEXT, currency_code TEXT,
              PRIMARY KEY (date, item_id, campaign, currency_code)
            ) WITHOUT ROWID;
            CREATE TEMP TABLE IF NOT EXISTS weekly_metrics_sales_keys (
              date TEXT, lsin TEXT, PRIMARY KEY (date, lsin)
            ) WITHOUT ROWID;
            DELETE FROM temp.weekly_metrics_ads_keys;
            DELETE FROM temp.weekly_metrics_sales_keys;
            INSERT OR IGNORE INTO temp.weekly_metrics_ads_keys
              SELECT a.date, a.item_id, a.campaign, a.currency_code
              FROM weekly_metrics_dirty_products d
              CROSS JOIN ads_product_daily a ON a.product_id = d.product_id;
            INSERT OR IGNORE INTO temp.weekly_metrics_sales_keys
              SELECT s.date, s.lsin FROM weekly_metrics_dirty_products d
              CROSS JOIN sales_daily s ON s.product_id = d.product_id;
            """)
    }

    func fetchWeeklyMetrics(
        productIds: [String],
        weekStarts: [String]
    ) throws -> [ProductWeeklyMetricsRecord] {
        guard !productIds.isEmpty, !weekStarts.isEmpty else { return [] }
        let uniqueIDs = Array(Set(productIds))
        return try dbQueue.read { db in
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            var records: [ProductWeeklyMetricsRecord] = []
            for start in stride(from: 0, to: uniqueIDs.count, by: 500) {
                try Task.checkCancellation()
                let chunk = uniqueIDs[start..<min(start + 500, uniqueIDs.count)]
                let idPlaceholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
                let sql = """
                SELECT *
                FROM product_weekly_metrics
                WHERE product_id IN (\(idPlaceholders))
                  AND week_start IN (\(weekPlaceholders));
                """
                var arguments = StatementArguments()
                for id in chunk { arguments += [id] }
                for week in weekStarts { arguments += [week] }
                records.append(contentsOf: try ProductWeeklyMetricsRecord.fetchAll(db, sql: sql, arguments: arguments))
            }
            return records
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
                       SUM(gross_sales_cents) AS gross_sales_cents,
                       SUM(gross_profit_cents) AS gross_profit_cents
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
                    grossSalesCents: row["gross_sales_cents"] ?? 0,
                    grossProfitCents: row["gross_profit_cents"] ?? 0
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
            let deleted = db.changesCount
            if deleted > 0, try db.tableExists("weekly_metrics_refresh_state") {
                // 删除事实已经提交后，重建失败/取消也能在下次启动恢复。
                try db.execute(sql: "UPDATE weekly_metrics_refresh_state SET initialized = 0 WHERE id = 1;")
            }
            return deleted
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
