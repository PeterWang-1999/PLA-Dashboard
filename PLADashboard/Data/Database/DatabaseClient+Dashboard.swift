import Foundation
import GRDB

extension DatabaseClient {
    func searchProductIDs(query: String, limit: Int = 500) throws -> [String] {
        try dbQueue.read { db in
            try searchProductIDs(query: query, limit: limit, db: db)
        }
    }

    func explainQueryPlan(sql: String, arguments: StatementArguments = StatementArguments()) throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)", arguments: arguments)
            return rows.compactMap { row in
                let detail: String? = row["detail"]
                let parent: Int? = row["parent"]
                let id: Int? = row["id"]
                if let detail {
                    return "[\(parent ?? 0).\(id ?? 0)] \(detail)"
                }
                return nil
            }
        }
    }

    private func searchProductIDs(query: String, limit: Int, db: Database) throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var ids = Set<String>()

        let ftsPattern = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        if !ftsPattern.isEmpty {
            let ftsRows = try Row.fetchAll(db, sql: """
                SELECT product_id
                FROM product_search
                WHERE product_search MATCH ?
                LIMIT ?;
                """, arguments: [ftsPattern, limit])
            for row in ftsRows {
                if let id: String = row["product_id"] {
                    ids.insert(id)
                }
            }
        }

        let likePattern = "%\(trimmed)%"
        let lsinRows = try Row.fetchAll(db, sql: """
            SELECT product_id
            FROM products
            WHERE lsin LIKE ? COLLATE NOCASE
               OR product_id LIKE ? COLLATE NOCASE
            LIMIT ?;
            """, arguments: [likePattern, likePattern, limit])
        for row in lsinRows {
            if let id: String = row["product_id"] {
                ids.insert(id)
            }
        }

        return Array(ids)
    }

    func fetchDashboardPage(
        filters: DashboardQueryFilters,
        page: Int,
        pageSize: Int
    ) throws -> DashboardPageResult {
        try Task.checkCancellation()
        let signpost = PerformanceSignposts.beginDashboardFetchPage()
        defer { PerformanceSignposts.endDashboardFetchPage(signpost) }

        let contextBundle = try loadDashboardMetricsContext()
        guard let contextBundle else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1, weekStarts: [])
        }

        return try fetchDashboardPageSQLPaginated(
            filters: filters,
            weekStarts: contextBundle.weekStarts,
            metricsContext: contextBundle.metricsContext,
            latestDay: contextBundle.latestDay,
            page: page,
            pageSize: pageSize
        )
    }

    static let dashboardExportRowLimit = 50_000

    /// 图表只需要筛选后的产品身份和报告窗口，不受 CSV 导出条数限制。
    func fetchDataDashboardProductSelection(
        filters: DashboardQueryFilters
    ) throws -> (productIDs: [String], weekStarts: [String]) {
        try Task.checkCancellation()
        guard let context = try loadDashboardMetricsContext() else { return ([], []) }
        let ranked = try fetchRankedProducts(
            filters: filters,
            weekStarts: context.weekStarts,
            limit: nil,
            offset: 0,
            includeTotalCount: false
        )
        return (ranked.products.map(\.productId), context.weekStarts)
    }

    func fetchDashboardAllRows(filters: DashboardQueryFilters) throws -> DashboardExportBundle {
        try Task.checkCancellation()
        let contextBundle = try loadDashboardMetricsContext()
        guard let contextBundle else {
            return DashboardExportBundle(rows: [], weekStarts: [], totalCount: 0)
        }

        let rows = try fetchAllMappedRows(
            filters: filters,
            weekStarts: contextBundle.weekStarts,
            metricsContext: contextBundle.metricsContext
        )

        guard rows.count <= Self.dashboardExportRowLimit else {
            throw DashboardExportError.tooManyRows(rows.count, limit: Self.dashboardExportRowLimit)
        }

        return DashboardExportBundle(
            rows: rows,
            weekStarts: contextBundle.weekStarts,
            totalCount: rows.count
        )
    }

    private struct DashboardMetricsContextBundle {
        let weekStarts: [String]
        let latestDay: String
        let metricsContext: DashboardMetricsCache
    }

    private func loadDashboardMetricsContext() throws -> DashboardMetricsContextBundle? {
        let latestDay = try fetchLatestMetricDay()
        guard let latestDay, let endDate = WeekCalendar.parseDay(latestDay) else {
            return nil
        }

        let completeWeekStarts = WeekCalendar.reportingWeekStarts(endingAt: endDate)
        guard !completeWeekStarts.isEmpty else { return nil }
        let weekStarts = WeekCalendar.trendWeekStarts(
            reportingWeekStarts: completeWeekStarts,
            latestDay: latestDay
        )

        let metricsContext: DashboardMetricsCache
        if let cached = cachedDashboardMetrics(for: weekStarts) {
            metricsContext = cached
        } else {
            let displayOverallWeeks = try fetchOverallWeeklyMetrics(weekStarts: weekStarts)
            let overallBenchmark = displayOverallWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
            let totalCostCents = overallBenchmark.costCents
            metricsContext = DashboardMetricsCache(
                weekStartsKey: weekStarts.cacheKey,
                overallBenchmark: overallBenchmark,
                totalCostCents: totalCostCents
            )
            storeDashboardMetricsCache(metricsContext)
        }

        return DashboardMetricsContextBundle(
            weekStarts: weekStarts,
            latestDay: latestDay,
            metricsContext: metricsContext
        )
    }

    private func fetchAllMappedRows(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        metricsContext: DashboardMetricsCache
    ) throws -> [ProductPerformanceRowModel] {
        let ranked = try fetchRankedProducts(
            filters: filters, weekStarts: weekStarts,
            limit: nil, offset: 0, includeTotalCount: false
        )
        return try mapProductsToPerformanceRows(
            products: ranked.products, weekStarts: weekStarts, metricsContext: metricsContext
        )
    }

    private func fetchDashboardPageSQLPaginated(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        metricsContext: DashboardMetricsCache,
        latestDay: String,
        page: Int,
        pageSize: Int
    ) throws -> DashboardPageResult {
        let ranked = try fetchRankedProducts(
            filters: filters,
            weekStarts: weekStarts,
            limit: pageSize,
            offset: max(0, (page - 1) * pageSize),
            includeTotalCount: true
        )

        guard ranked.totalCount > 0, !ranked.products.isEmpty else {
            return DashboardPageResult(
                rows: [], totalCount: 0, totalPages: 1,
                weekStarts: weekStarts, latestDataDay: latestDay
            )
        }

        let totalPages = max(1, Int(ceil(Double(ranked.totalCount) / Double(pageSize))))
        let pageRows = try mapProductsToPerformanceRows(
            products: ranked.products,
            weekStarts: weekStarts,
            metricsContext: metricsContext
        )

        return DashboardPageResult(
            rows: pageRows,
            totalCount: ranked.totalCount,
            totalPages: totalPages,
            weekStarts: weekStarts,
            latestDataDay: latestDay
        )
    }

    private struct RankedProductsResult {
        let products: [ProductRecord]
        let totalCount: Int
    }

    private func fetchRankedProducts(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        limit: Int?,
        offset: Int,
        includeTotalCount: Bool
    ) throws -> RankedProductsResult {
        return try dbQueue.read { db in
            let filterClause = try buildProductFilterClause(filters: filters, weekStarts: weekStarts, db: db)
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            let countSQL = """
                SELECT COUNT(*) FROM (
                  SELECT p.product_id
                  FROM products p
                  INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
                  WHERE m.week_start IN (\(weekPlaceholders))
                  \(filterClause.sql)
                  GROUP BY p.product_id
                  HAVING SUM(m.cost_cents) > 0 OR SUM(m.conversion_value_cents) > 0
                );
                """
            var countArgs = StatementArguments()
            for week in weekStarts { countArgs += [week] }
            countArgs += filterClause.arguments

            let totalCount: Int
            if includeTotalCount {
                // 同一连接的写入及其他连接的提交均会使计数失效。
                // 排序、页码不改变筛选集合；仅保留最近一个集合，限制缓存大小。
                var countFilters = filters
                countFilters.sort = .default
                let revision = try Int.fetchOne(db, sql: "SELECT total_changes();") ?? 0
                let dataVersion = try Int.fetchOne(db, sql: "PRAGMA data_version;") ?? 0
                if let cached = dashboardCountCache,
                   cached.filters == countFilters, cached.weekStarts == weekStarts,
                   cached.revision == revision, cached.dataVersion == dataVersion {
                    totalCount = cached.count
                } else {
                    totalCount = try Int.fetchOne(db, sql: countSQL, arguments: countArgs) ?? 0
                    dashboardCountCache = DashboardCountCache(
                        filters: countFilters, weekStarts: weekStarts,
                        revision: revision, dataVersion: dataVersion, count: totalCount
                    )
                }
            } else {
                totalCount = 0
            }

            var dataSQL = """
                SELECT p.*
                FROM products p
                INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
                WHERE m.week_start IN (\(weekPlaceholders))
                \(filterClause.sql)
                GROUP BY p.product_id
                HAVING SUM(m.cost_cents) > 0 OR SUM(m.conversion_value_cents) > 0
                ORDER BY \(filters.sort.sqlOrderClause)
                """
            var dataArgs = StatementArguments()
            for week in weekStarts { dataArgs += [week] }
            dataArgs += filterClause.arguments

            if let limit {
                dataSQL += " LIMIT ? OFFSET ?;"
                dataArgs += [limit, offset]
            } else {
                dataSQL += ";"
            }

            let products = try ProductRecord.fetchAll(db, sql: dataSQL, arguments: dataArgs)
            return RankedProductsResult(products: products, totalCount: totalCount)
        }
    }

    private struct ProductFilterClause {
        let sql: String
        let arguments: StatementArguments
    }

    private func buildProductFilterClause(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        db: Database
    ) throws -> ProductFilterClause {
        var sql = ""
        var arguments = StatementArguments()

        let search = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            let searchIDs = try searchProductIDs(query: search, limit: 500, db: db)
            if searchIDs.isEmpty {
                sql += " AND 1 = 0"
            } else {
                let placeholders = Array(repeating: "?", count: searchIDs.count).joined(separator: ", ")
                sql += " AND p.product_id IN (\(placeholders))"
                for id in searchIDs { arguments += [id] }
            }
        }

        switch filters.customLabelFilter.sqlClause {
        case .none:
            break
        case .columnNotEmpty(let column):
            sql += " AND p.\(column) IS NOT NULL AND TRIM(p.\(column)) != ''"
        case .equals(let column, let value):
            sql += " AND p.\(column) = ?"
            arguments += [value]
        }

        if let categoryMatch = filters.categoryFilter.sqlMatch {
            sql += """
             AND (
                p.google_product_category LIKE ?
                OR p.google_product_category LIKE ?
             )
            """
            arguments += [categoryMatch.exactSuffixPattern, categoryMatch.nestedSuffixPattern]
        }

        _ = weekStarts
        return ProductFilterClause(sql: sql, arguments: arguments)
    }

    private func mapProductsToPerformanceRows(
        products: [ProductRecord],
        weekStarts: [String],
        metricsContext: DashboardMetricsCache
    ) throws -> [ProductPerformanceRowModel] {
        guard !products.isEmpty else { return [] }

        let productIds = products.map(\.productId)
        let latestDay = try fetchLatestMetricDay() ?? weekStarts.last ?? ""
        let trendWeekStarts = weekStarts
        let completeWeekStarts = WeekCalendar.reportingWeekStarts(
            endingAt: WeekCalendar.parseDay(latestDay) ?? Date()
        )
        let trendCoverageDays = trendWeekStarts.map { weekStart in
            completeWeekStarts.contains(weekStart)
                ? 7
                : WeekCalendar.coveredDayCount(weekStart: weekStart, through: latestDay)
        }
        let weeklyRecords = try fetchWeeklyMetrics(productIds: productIds, weekStarts: trendWeekStarts)
        let weeklyByProduct = Dictionary(grouping: weeklyRecords, by: \.productId)

        return try products.compactMap { product in
            try makePerformanceRow(
                product: product,
                weekStarts: weekStarts,
                trendWeekStarts: trendWeekStarts,
                trendCoverageDays: trendCoverageDays,
                weeklyByProduct: weeklyByProduct,
                metricsContext: metricsContext
            )
        }
    }

    private func makePerformanceRow(
        product: ProductRecord,
        weekStarts: [String],
        trendWeekStarts: [String],
        trendCoverageDays: [Int],
        weeklyByProduct: [String: [ProductWeeklyMetricsRecord]],
        metricsContext: DashboardMetricsCache
    ) throws -> ProductPerformanceRowModel? {
        let records = weeklyByProduct[product.productId] ?? []
        let recordByWeek = Dictionary(uniqueKeysWithValues: records.map { ($0.weekStart, $0) })

        let displayPeriodTotals = trendWeekStarts
            .map { recordByWeek[$0]?.aggregatedMetrics ?? AggregatedMetrics() }
            .reduce(AggregatedMetrics()) { $0 + $1 }
        guard displayPeriodTotals.costCents > 0 || displayPeriodTotals.conversionValueCents > 0 else { return nil }

        let costTrend = trendWeekStarts.map { recordByWeek[$0]?.costCents ?? 0 }
        let gsTrend = trendWeekStarts.map { recordByWeek[$0]?.conversionValueCents ?? 0 }

        return ProductPerformanceRowMapper.map(
            product: product,
            displayPeriodTotals: displayPeriodTotals,
            totalCostCents: metricsContext.totalCostCents,
            overallBenchmark: metricsContext.overallBenchmark,
            weeklyCostTrend: costTrend,
            weeklyGSTrend: gsTrend,
            trendWeekStarts: trendWeekStarts,
            trendCoverageDays: trendCoverageDays
        )
    }

    private func parseCurrency(_ value: String) -> Double {
        let cleaned = value.replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0
    }
}
