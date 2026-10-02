import Foundation
import GRDB

extension DatabaseClient {
    func fetchDataDashboard(
        filters: DashboardQueryFilters,
        accountKind: WorkspaceAccountKind
    ) throws -> DataDashboardSnapshot {
        try Task.checkCancellation()
        let selection = try fetchDataDashboardProductSelection(filters: filters)
        guard !selection.productIDs.isEmpty else { return .empty }

        let productIDs = selection.productIDs
        let weekStarts = selection.weekStarts
        let weekly = try fetchDashboardWeeklyAggregates(productIDs: productIDs, weekStarts: weekStarts)
        let overallWeekly = try fetchOverallWeeklyMetrics(weekStarts: weekStarts)
        let overallByWeek = Dictionary(uniqueKeysWithValues: overallWeekly.map { ($0.weekStart, $0.metrics) })
        let totals = weekly.map(\.metrics).reduce(AggregatedMetrics(), +)
        let overallTotals = overallWeekly.map(\.metrics).reduce(AggregatedMetrics(), +)

        let latestDay = try fetchLatestMetricDay()
        let daily = try latestDay.map { try fetchDashboardDailyTrend(productIDs: productIDs, through: $0) } ?? []
        let campaigns = accountKind == .thirdParty
            ? try fetchDashboardCampaigns(
                productIDs: productIDs,
                from: weekStarts.first,
                through: latestDay
            )
            : []
        let categories = try fetchDashboardCategories(
            productIDs: productIDs,
            weekStarts: weekStarts,
            portfolioMetrics: totals
        )
        let products = try fetchDashboardTopProducts(productIDs: productIDs, weekStarts: weekStarts)

        return DataDashboardSnapshot(
            metrics: makeDashboardMetrics(
                filteredWeeks: weekly,
                overallByWeek: overallByWeek,
                totals: totals,
                overallTotals: overallTotals
            ),
            weeklyTrend: weekly.map {
                DataDashboardTrendPoint(
                    period: $0.weekStart,
                    displayLabel: WeekCalendar.plaWeekLabel(forWeekStartDay: $0.weekStart) ?? $0.weekStart,
                    costCents: $0.metrics.costCents,
                    salesCents: $0.metrics.conversionValueCents,
                    roi: $0.metrics.roi,
                    cvr: $0.metrics.cvr,
                    cpc: $0.metrics.cpc,
                    aos: $0.metrics.aos
                )
            },
            dailyTrend: daily,
            campaigns: campaigns,
            categories: categories,
            topProducts: products,
            reportingPeriodLabel: WeekCalendar.dashboardDataPeriodLabel(
                weekStarts: weekStarts,
                latestDay: latestDay
            )
        )
    }

    /// 每个批次只返回每周汇总，不把全部产品的逐周记录带回内存。
    private func fetchDashboardWeeklyAggregates(
        productIDs: [String], weekStarts: [String]
    ) throws -> [WeeklyProductMetrics] {
        var byWeek: [String: AggregatedMetrics] = [:]
        try dbQueue.read { db in
            for chunk in productIDs.chunked(maxCount: 500) {
                try Task.checkCancellation()
                var arguments = StatementArguments()
                for id in chunk { arguments += [id] }
                for week in weekStarts { arguments += [week] }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT week_start, \(Self.dashboardMetricsProjection)
                    FROM product_weekly_metrics
                    WHERE product_id IN (\(chunk.placeholders))
                      AND week_start IN (\(weekStarts.placeholders))
                    GROUP BY week_start;
                    """, arguments: arguments)
                for row in rows {
                    let week: String = row["week_start"]
                    byWeek[week, default: AggregatedMetrics()] =
                        byWeek[week, default: AggregatedMetrics()] + Self.dashboardAggregate(row)
                }
            }
        }
        return weekStarts.map {
            WeeklyProductMetrics(productId: "__dashboard__", weekStart: $0, metrics: byWeek[$0] ?? AggregatedMetrics())
        }
    }

    private static let dashboardMetricsProjection = """
        SUM(cost_cents) AS cost_cents, SUM(impressions) AS impressions,
        SUM(clicks) AS clicks, SUM(conversions) AS conversions,
        SUM(conversion_value_cents) AS conversion_value_cents,
        SUM(gross_sales_cents) AS gross_sales_cents, SUM(gross_profit_cents) AS gross_profit_cents
        """

    private static func dashboardAggregate(_ row: Row) -> AggregatedMetrics {
        AggregatedMetrics(
            costCents: row["cost_cents"] ?? 0, impressions: row["impressions"] ?? 0,
            clicks: row["clicks"] ?? 0, conversions: row["conversions"] ?? 0,
            conversionValueCents: row["conversion_value_cents"] ?? 0,
            grossSalesCents: row["gross_sales_cents"] ?? 0, grossProfitCents: row["gross_profit_cents"] ?? 0
        )
    }

    private func makeDashboardMetrics(
        filteredWeeks: [WeeklyProductMetrics],
        overallByWeek: [String: AggregatedMetrics],
        totals: AggregatedMetrics,
        overallTotals: AggregatedMetrics
    ) -> [DataDashboardMetric] {
        let current = filteredWeeks.last?.metrics ?? AggregatedMetrics()
        let previous = filteredWeeks.dropLast().last?.metrics ?? AggregatedMetrics()
        let currentOverall = filteredWeeks.last.flatMap { overallByWeek[$0.weekStart] } ?? AggregatedMetrics()
        let previousOverall = filteredWeeks.dropLast().last.flatMap { overallByWeek[$0.weekStart] } ?? AggregatedMetrics()

        func share(_ value: Int, _ total: Int) -> Double? {
            total > 0 ? Double(value) / Double(total) : nil
        }
        func relative(_ value: Double, _ previous: Double) -> Double? {
            previous != 0 ? (value - previous) / abs(previous) : nil
        }
        func average(_ keyPath: KeyPath<AggregatedMetrics, Double>) -> Double {
            let values = filteredWeeks.map { $0.metrics[keyPath: keyPath] }.filter { $0.isFinite }
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        func comparison(_ value: Double?, percentagePoints: Bool = false) -> (String, ComparisonDirection) {
            guard let value, value.isFinite else { return ("—", .neutral) }
            let formatted = percentagePoints
                ? String(format: "%+.2f pp", value * 100)
                : String(format: "%+.1f%%", value * 100)
            return (formatted, value > 0 ? .positive : (value < 0 ? .negative : .neutral))
        }

        let costShare = share(totals.costCents, overallTotals.costCents)
        let salesShare = share(totals.conversionValueCents, overallTotals.conversionValueCents)
        let costShareDelta = comparison(
            (share(current.costCents, currentOverall.costCents) ?? 0)
                - (share(previous.costCents, previousOverall.costCents) ?? 0),
            percentagePoints: true
        )
        let salesShareDelta = comparison(
            (share(current.conversionValueCents, currentOverall.conversionValueCents) ?? 0)
                - (share(previous.conversionValueCents, previousOverall.conversionValueCents) ?? 0),
            percentagePoints: true
        )
        let roiDelta = comparison(relative(current.roi, previous.roi))
        let cvrDelta = comparison(relative(current.cvr, previous.cvr))
        let cpcDelta = comparison(relative(current.cpc, previous.cpc))
        let aosDelta = comparison(relative(current.aos, previous.aos))

        return [
            DataDashboardMetric(
                kind: .spend,
                title: "消费总额",
                value: totals.currency(\.costCents),
                reference: "占比 \(costShare.percent)",
                comparisonLabel: "近 2 周占比环比",
                comparison: costShareDelta.0,
                comparisonDirection: costShareDelta.1
            ),
            DataDashboardMetric(
                kind: .sales,
                title: "销售总额",
                value: totals.currency(\.conversionValueCents),
                reference: "占比 \(salesShare.percent)",
                comparisonLabel: "近 2 周占比环比",
                comparison: salesShareDelta.0,
                comparisonDirection: salesShareDelta.1
            ),
            DataDashboardMetric(
                kind: .roi,
                title: "广告 ROI",
                value: totals.roi.decimal,
                reference: "均值 \(average(\.roi).decimal)",
                comparisonLabel: "近 2 周环比",
                comparison: roiDelta.0,
                comparisonDirection: roiDelta.1
            ),
            DataDashboardMetric(
                kind: .cvr,
                title: "CVR",
                value: totals.cvr.percent,
                reference: "均值 \(average(\.cvr).percent)",
                comparisonLabel: "近 2 周环比",
                comparison: cvrDelta.0,
                comparisonDirection: cvrDelta.1
            ),
            DataDashboardMetric(
                kind: .cpc,
                title: "CPC",
                value: totals.cpc.currency,
                reference: "均值 \(average(\.cpc).currency)",
                comparisonLabel: "近 2 周环比",
                comparison: cpcDelta.0,
                comparisonDirection: cpcDelta.1 == .positive ? .negative : cpcDelta.1 == .negative ? .positive : .neutral
            ),
            DataDashboardMetric(
                kind: .aos,
                title: "AOS",
                value: totals.aos.currency,
                reference: "均值 \(average(\.aos).currency)",
                comparisonLabel: "近 2 周环比",
                comparison: aosDelta.0,
                comparisonDirection: aosDelta.1
            ),
        ]
    }

    private func fetchDashboardDailyTrend(productIDs: [String], through latestDay: String) throws -> [DataDashboardTrendPoint] {
        guard let end = WeekCalendar.parseDay(latestDay) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .day, value: -13, to: end) else { return [] }
        let startDay = WeekCalendar.formatDay(start)
        var byDay: [String: AggregatedMetrics] = [:]

        for chunk in productIDs.chunked(maxCount: 500) {
            try Task.checkCancellation()
            try dbQueue.read { db in
                let placeholders = chunk.placeholders
                var arguments: StatementArguments = [ImportJobStatus.succeeded.rawValue, startDay, latestDay]
                for productID in chunk { arguments += [productID] }
                let rows = try Row.fetchAll(db, sql: """
                    WITH ranked AS (
                      SELECT a.*, ROW_NUMBER() OVER (
                        PARTITION BY a.date, a.item_id, a.campaign, a.currency_code
                        ORDER BY j.imported_at DESC, a.rowid DESC
                      ) AS rn
                      FROM ads_product_daily a
                      INNER JOIN import_jobs j ON j.id = a.import_id
                      WHERE j.status = ? AND a.date BETWEEN ? AND ?
                        AND a.product_id IN (\(placeholders))
                    )
                    SELECT date, SUM(cost_micros) / 10000 AS cost_cents,
                           SUM(clicks) AS clicks, SUM(conversions) AS conversions,
                           SUM(conversion_value_cents) AS sales_cents
                    FROM ranked WHERE rn = 1 GROUP BY date;
                    """, arguments: arguments)
                for row in rows {
                    guard let day: String = row["date"] else { continue }
                    byDay[day, default: AggregatedMetrics()] = byDay[day, default: AggregatedMetrics()] + AggregatedMetrics(
                        costCents: row["cost_cents"] ?? 0,
                        clicks: row["clicks"] ?? 0,
                        conversions: row["conversions"] ?? 0,
                        conversionValueCents: row["sales_cents"] ?? 0
                    )
                }
            }
        }

        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = WeekCalendar.formatDay(date)
            let metrics = byDay[day] ?? AggregatedMetrics()
            return DataDashboardTrendPoint(
                period: day,
                displayLabel: String(day.suffix(5)).replacingOccurrences(of: "-", with: "/"),
                costCents: metrics.costCents,
                salesCents: metrics.conversionValueCents,
                roi: metrics.roi,
                cvr: metrics.cvr,
                cpc: metrics.cpc,
                aos: metrics.aos
            )
        }
    }

    private func fetchDashboardCampaigns(
        productIDs: [String],
        from startDay: String?,
        through latestDay: String?
    ) throws -> [DataDashboardCampaignRow] {
        guard let startDay, let latestDay else { return [] }
        var merged: [String: AggregatedMetrics] = [:]
        for chunk in productIDs.chunked(maxCount: 500) {
            try Task.checkCancellation()
            try dbQueue.read { db in
                var arguments: StatementArguments = [ImportJobStatus.succeeded.rawValue, startDay, latestDay]
                for productID in chunk { arguments += [productID] }
                let rows = try Row.fetchAll(db, sql: """
                    WITH ranked AS (
                      SELECT a.*, ROW_NUMBER() OVER (
                        PARTITION BY a.date, a.item_id, a.campaign, a.currency_code
                        ORDER BY j.imported_at DESC, a.rowid DESC
                      ) AS rn
                      FROM ads_product_daily a
                      INNER JOIN import_jobs j ON j.id = a.import_id
                      WHERE j.status = ? AND a.date BETWEEN ? AND ?
                        AND a.product_id IN (\(chunk.placeholders))
                    )
                    SELECT campaign, SUM(cost_micros) / 10000 AS cost_cents,
                           SUM(clicks) AS clicks, SUM(conversions) AS conversions,
                           SUM(conversion_value_cents) AS sales_cents
                    FROM ranked WHERE rn = 1 GROUP BY campaign;
                    """, arguments: arguments)
                for row in rows {
                    guard let campaign: String = row["campaign"] else { continue }
                    merged[campaign, default: AggregatedMetrics()] = merged[campaign, default: AggregatedMetrics()] + AggregatedMetrics(
                        costCents: row["cost_cents"] ?? 0,
                        clicks: row["clicks"] ?? 0,
                        conversions: row["conversions"] ?? 0,
                        conversionValueCents: row["sales_cents"] ?? 0
                    )
                }
            }
        }
        return merged.map(DataDashboardCampaignRow.init(campaign:metrics:))
            .sorted { $0.metrics.costCents > $1.metrics.costCents }
            .prefix(20).map { $0 }
    }

    private func fetchDashboardCategories(
        productIDs: [String],
        weekStarts: [String],
        portfolioMetrics: AggregatedMetrics
    ) throws -> [DataDashboardCategoryPoint] {
        var merged: [String: [String: AggregatedMetrics]] = [:]
        for chunk in productIDs.chunked(maxCount: 500) {
            try Task.checkCancellation()
            try dbQueue.read { db in
                var arguments = StatementArguments()
                for productID in chunk { arguments += [productID] }
                for weekStart in weekStarts { arguments += [weekStart] }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT COALESCE(NULLIF(TRIM(p.pla_cms3), ''), NULLIF(TRIM(p.google_product_category), ''), '未分类') AS category,
                           m.week_start,
                           SUM(m.cost_cents) AS cost_cents, SUM(m.clicks) AS clicks,
                           SUM(m.conversions) AS conversions, SUM(m.conversion_value_cents) AS sales_cents
                    FROM product_weekly_metrics m
                    INNER JOIN products p ON p.product_id = m.product_id
                    WHERE m.product_id IN (\(chunk.placeholders))
                      AND m.week_start IN (\(weekStarts.placeholders))
                    GROUP BY category, m.week_start;
                    """, arguments: arguments)
                for row in rows {
                    guard let raw: String = row["category"] else { continue }
                    guard let weekStart: String = row["week_start"] else { continue }
                    let category = raw.components(separatedBy: ">").last?.trimmingCharacters(in: .whitespaces) ?? raw
                    let metrics = AggregatedMetrics(
                        costCents: row["cost_cents"] ?? 0,
                        clicks: row["clicks"] ?? 0,
                        conversions: row["conversions"] ?? 0,
                        conversionValueCents: row["sales_cents"] ?? 0
                    )
                    merged[category, default: [:]][weekStart, default: AggregatedMetrics()] =
                        merged[category, default: [:]][weekStart, default: AggregatedMetrics()] + metrics
                }
            }
        }
        let currentWeek = weekStarts.last
        let previousWeek = weekStarts.dropLast().last
        return merged.map { category, byWeek in
            let metrics = weekStarts.compactMap { byWeek[$0] }.reduce(AggregatedMetrics(), +)
            return DataDashboardCategoryPoint(
                category: category,
                metrics: metrics,
                currentWeekMetrics: currentWeek.flatMap { byWeek[$0] } ?? AggregatedMetrics(),
                previousWeekMetrics: previousWeek.flatMap { byWeek[$0] } ?? AggregatedMetrics(),
                spendShare: portfolioMetrics.costCents > 0
                    ? Double(metrics.costCents) / Double(portfolioMetrics.costCents) : 0,
                salesShare: portfolioMetrics.conversionValueCents > 0
                    ? Double(metrics.conversionValueCents) / Double(portfolioMetrics.conversionValueCents) : 0,
                portfolioROI: portfolioMetrics.roi
            )
        }
            .sorted { $0.metrics.costCents > $1.metrics.costCents }
            .prefix(15).map { $0 }
    }

    private func fetchDashboardTopProducts(
        productIDs: [String],
        weekStarts: [String]
    ) throws -> [DataDashboardProduct] {
        struct Candidate {
            let id: String
            let position: Int
            let metrics: AggregatedMetrics
        }
        var candidates: [Candidate] = []
        try dbQueue.read { db in
            for (batch, chunk) in productIDs.chunked(maxCount: 500).enumerated() {
                try Task.checkCancellation()
                // 位置是内部数组索引；产品身份与周仍用绑定参数。
                let scope = chunk.enumerated().map { "(?, \(batch * 500 + $0.offset))" }.joined(separator: ",")
                var arguments = StatementArguments()
                for id in chunk { arguments += [id] }
                for week in weekStarts { arguments += [week] }
                let rows = try Row.fetchAll(db, sql: """
                    WITH selected(product_id, position) AS (VALUES \(scope))
                    SELECT m.product_id, s.position, \(Self.dashboardMetricsProjection)
                    FROM product_weekly_metrics m
                    INNER JOIN selected s ON s.product_id = m.product_id
                    WHERE m.week_start IN (\(weekStarts.placeholders))
                    GROUP BY m.product_id, s.position
                    ORDER BY cost_cents DESC, s.position ASC LIMIT 10;
                    """, arguments: arguments)
                for row in rows {
                    candidates.append(Candidate(id: row["product_id"], position: row["position"], metrics: Self.dashboardAggregate(row)))
                }
            }
        }
        // 每批前十必然包含全局前十的候选；同花费时保持原筛选顺序。
        let top = candidates.sorted {
            $0.metrics.costCents == $1.metrics.costCents
                ? $0.position < $1.position : $0.metrics.costCents > $1.metrics.costCents
        }.prefix(10)
        let ids = top.map(\.id)
        let metricsByID = Dictionary(uniqueKeysWithValues: top.map { ($0.id, $0.metrics) })
        let products = try dbQueue.read { db in
            var arguments = StatementArguments()
            for productID in ids { arguments += [productID] }
            return try ProductRecord.fetchAll(
                db,
                sql: "SELECT * FROM products WHERE product_id IN (\(ids.placeholders));",
                arguments: arguments
            )
        }
        let productByID = Dictionary(uniqueKeysWithValues: products.map { ($0.productId, $0) })
        return ids.map { id in
            let product = productByID[id]
            return DataDashboardProduct(
                productID: id,
                title: product?.title?.nilIfBlank ?? product?.lsin ?? id,
                imageURL: product?.imageUrl.flatMap(URL.init(string:)),
                metrics: metricsByID[id] ?? AggregatedMetrics()
            )
        }
    }
}

private extension Array where Element == String {
    var placeholders: String { Array(repeating: "?", count: count).joined(separator: ", ") }
    func chunked(maxCount: Int) -> [[String]] {
        stride(from: 0, to: count, by: maxCount).map { Array(self[$0..<Swift.min($0 + maxCount, count)]) }
    }
}

private extension AggregatedMetrics {
    func currency(_ keyPath: KeyPath<AggregatedMetrics, Int>) -> String {
        "$" + DashboardMetricFormatter.formatCurrencyFromCents(self[keyPath: keyPath])
    }
}

private extension Optional where Wrapped == Double {
    var percent: String { map { $0.percent } ?? "—" }
}

private extension Double {
    var decimal: String { DashboardMetricFormatter.formatDecimal(self) }
    var percent: String { DashboardMetricFormatter.formatPercentValue(self) }
    var currency: String { "$" + DashboardMetricFormatter.formatDecimal(self) }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
