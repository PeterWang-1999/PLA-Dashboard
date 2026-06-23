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
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM product_weekly_metrics;")

            let adsDaily = try fetchDedupedAdsDaily(db: db)

            var buckets: [String: [String: AggregatedMetrics]] = [:]

            for row in adsDaily {
                guard let weekStart = WeekCalendar.weekStartSunday(forDay: row.date) else { continue }
                var weekMap = buckets[row.productId, default: [:]]
                var metrics = weekMap[weekStart, default: AggregatedMetrics()]
                metrics.costCents += WeekCalendar.microsToCents(row.costMicros)
                metrics.impressions += row.impressions
                metrics.clicks += row.clicks
                metrics.conversions += row.conversions
                metrics.conversionValueCents += row.conversionValueCents
                weekMap[weekStart] = metrics
                buckets[row.productId] = weekMap
            }

            var records: [ProductWeeklyMetricsRecord] = []
            records.reserveCapacity(buckets.values.reduce(0) { $0 + $1.count })

            for (productId, weekMap) in buckets {
                for (weekStart, metrics) in weekMap {
                    records.append(ProductWeeklyMetricsRecord.make(
                        productId: productId,
                        weekStart: weekStart,
                        metrics: metrics
                    ))
                }
            }

            for record in records {
                try record.insert(db, onConflict: .replace)
            }
        }
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

    private struct DedupedAdsDailyRow: FetchableRecord, Decodable {
        let productId: String
        let date: String
        let costMicros: Int
        let impressions: Int
        let clicks: Int
        let conversions: Double
        let conversionValueCents: Int

        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case date
            case costMicros = "cost_micros"
            case impressions
            case clicks
            case conversions
            case conversionValueCents = "conversion_value_cents"
        }
    }

    private func fetchDedupedAdsDaily(db: Database) throws -> [DedupedAdsDailyRow] {
        try DedupedAdsDailyRow.fetchAll(db, sql: """
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
                SUM(cost_micros) AS cost_micros,
                SUM(impressions) AS impressions,
                SUM(clicks) AS clicks,
                SUM(conversions) AS conversions,
                SUM(conversion_value_cents) AS conversion_value_cents
            FROM ranked
            WHERE rn = 1
            GROUP BY product_id, date;
            """, arguments: [ImportJobStatus.succeeded.rawValue])
    }
}
