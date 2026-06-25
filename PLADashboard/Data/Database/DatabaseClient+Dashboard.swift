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
        let signpost = PerformanceSignposts.beginDashboardFetchPage()
        defer { PerformanceSignposts.endDashboardFetchPage(signpost) }

        let contextBundle = try loadDashboardMetricsContext()
        guard let contextBundle else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        let hasAlertFilter = alertFilterLabel(for: filters.alertFilter) != nil

        if hasAlertFilter {
            return try fetchDashboardPageWithAlertFilter(
                filters: filters,
                weekStarts: contextBundle.weekStarts,
                metricsContext: contextBundle.metricsContext,
                page: page,
                pageSize: pageSize
            )
        }

        return try fetchDashboardPageSQLPaginated(
            filters: filters,
            weekStarts: contextBundle.weekStarts,
            metricsContext: contextBundle.metricsContext,
            page: page,
            pageSize: pageSize
        )
    }

    static let dashboardExportRowLimit = 50_000

    func fetchDashboardAllRows(filters: DashboardQueryFilters) throws -> DashboardExportBundle {
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
        let metricsContext: DashboardMetricsCache
    }

    private func loadDashboardMetricsContext() throws -> DashboardMetricsContextBundle? {
        let latestDay = try fetchLatestMetricDay()
        guard let latestDay, let endDate = WeekCalendar.parseDay(latestDay) else {
            return nil
        }

        let weekStarts = WeekCalendar.reportingWeekStarts(endingAt: endDate)
        guard !weekStarts.isEmpty else { return nil }

        let metricsContext: DashboardMetricsCache
        if let cached = cachedDashboardMetrics(for: weekStarts) {
            metricsContext = cached
        } else {
            let overallWeeks = try fetchOverallWeeklyMetrics(weekStarts: weekStarts)
            let cohortBenchmarks = try fetchWeeklyCohortSpendBenchmarks(weekStarts: weekStarts)
            let overallBenchmark = overallWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
            let totalCostCents = overallBenchmark.costCents
            metricsContext = DashboardMetricsCache(
                weekStartsKey: weekStarts.cacheKey,
                overallWeeks: overallWeeks,
                cohortBenchmarks: cohortBenchmarks,
                overallBenchmark: overallBenchmark,
                totalCostCents: totalCostCents
            )
            storeDashboardMetricsCache(metricsContext)
        }

        return DashboardMetricsContextBundle(weekStarts: weekStarts, metricsContext: metricsContext)
    }

    private func fetchAllMappedRows(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        metricsContext: DashboardMetricsCache
    ) throws -> [ProductPerformanceRowModel] {
        if alertFilterLabel(for: filters.alertFilter) != nil {
            let batchSize = 200
            var offset = 0
            var mappedRows: [ProductPerformanceRowModel] = []

            while true {
                let ranked = try fetchRankedProducts(
                    filters: filters,
                    weekStarts: weekStarts,
                    limit: batchSize,
                    offset: offset,
                    includeTotalCount: false
                )
                if ranked.products.isEmpty { break }

                let batchRows = try mapProductsToPerformanceRows(
                    products: ranked.products,
                    weekStarts: weekStarts,
                    metricsContext: metricsContext,
                    alertFilter: filters.alertFilter
                )
                mappedRows.append(contentsOf: batchRows)

                if ranked.products.count < batchSize { break }
                offset += batchSize
            }

            mappedRows.sort { lhs, rhs in
                filters.sort.sortsBefore(lhs, rhs)
            }
            return mappedRows
        }

        let ranked = try fetchRankedProducts(
            filters: filters,
            weekStarts: weekStarts,
            limit: nil,
            offset: 0,
            includeTotalCount: false
        )
        return try mapProductsToPerformanceRows(
            products: ranked.products,
            weekStarts: weekStarts,
            metricsContext: metricsContext,
            alertFilter: nil
        )
    }

    private func fetchDashboardPageSQLPaginated(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        metricsContext: DashboardMetricsCache,
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
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        let totalPages = max(1, Int(ceil(Double(ranked.totalCount) / Double(pageSize))))
        let pageRows = try mapProductsToPerformanceRows(
            products: ranked.products,
            weekStarts: weekStarts,
            metricsContext: metricsContext,
            alertFilter: nil
        )

        return DashboardPageResult(rows: pageRows, totalCount: ranked.totalCount, totalPages: totalPages)
    }

    private func fetchDashboardPageWithAlertFilter(
        filters: DashboardQueryFilters,
        weekStarts: [String],
        metricsContext: DashboardMetricsCache,
        page: Int,
        pageSize: Int
    ) throws -> DashboardPageResult {
        let batchSize = 200
        var offset = 0
        var mappedRows: [ProductPerformanceRowModel] = []

        while true {
            let ranked = try fetchRankedProducts(
                filters: filters,
                weekStarts: weekStarts,
                limit: batchSize,
                offset: offset,
                includeTotalCount: false
            )

            if ranked.products.isEmpty { break }

            let batchRows = try mapProductsToPerformanceRows(
                products: ranked.products,
                weekStarts: weekStarts,
                metricsContext: metricsContext,
                alertFilter: filters.alertFilter
            )
            mappedRows.append(contentsOf: batchRows)

            if ranked.products.count < batchSize { break }
            offset += batchSize
        }

        guard !mappedRows.isEmpty else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        mappedRows.sort { lhs, rhs in
            filters.sort.sortsBefore(lhs, rhs)
        }

        let totalCount = mappedRows.count
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        let safePage = min(max(page, 1), totalPages)
        let start = (safePage - 1) * pageSize
        let end = min(start + pageSize, totalCount)
        let pageRows = start < end ? Array(mappedRows[start..<end]) : []

        return DashboardPageResult(rows: pageRows, totalCount: totalCount, totalPages: totalPages)
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
        try dbQueue.read { db in
            let filterClause = try buildProductFilterClause(filters: filters, weekStarts: weekStarts, db: db)
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")

            var countSQL = """
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
                totalCount = try Int.fetchOne(db, sql: countSQL, arguments: countArgs) ?? 0
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
        metricsContext: DashboardMetricsCache,
        alertFilter: String?
    ) throws -> [ProductPerformanceRowModel] {
        guard !products.isEmpty else { return [] }

        let productIds = products.map(\.productId)
        let weeklyRecords = try fetchWeeklyMetrics(productIds: productIds, weekStarts: weekStarts)
        let weeklyByProduct = Dictionary(grouping: weeklyRecords, by: \.productId)

        return try products.compactMap { product in
            try makePerformanceRowIfMatchingAlert(
                product: product,
                weekStarts: weekStarts,
                weeklyByProduct: weeklyByProduct,
                metricsContext: metricsContext,
                alertFilter: alertFilter
            )
        }
    }

    private func makePerformanceRowIfMatchingAlert(
        product: ProductRecord,
        weekStarts: [String],
        weeklyByProduct: [String: [ProductWeeklyMetricsRecord]],
        metricsContext: DashboardMetricsCache,
        alertFilter: String?
    ) throws -> ProductPerformanceRowModel? {
        let records = weeklyByProduct[product.productId] ?? []
        let recordByWeek = Dictionary(uniqueKeysWithValues: records.map { ($0.weekStart, $0) })

        let productWeeks: [WeeklyProductMetrics] = weekStarts.map { week in
            let metrics = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
            return WeeklyProductMetrics(productId: product.productId, weekStart: week, metrics: metrics)
        }

        let sixWeekTotals = productWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
        guard sixWeekTotals.costCents > 0 || sixWeekTotals.conversionValueCents > 0 else { return nil }

        let warning = WeeklyMetricsRules.resolveWarningLabel(
            productWeeks: productWeeks,
            overallWeeks: metricsContext.overallWeeks,
            cohortBenchmarks: metricsContext.cohortBenchmarks,
            totalPortfolioCostCents: metricsContext.totalCostCents,
            settings: AnalyticsSettingsSnapshot.current(accountID: accountID)
        )

        if let required = alertFilterLabel(for: alertFilter ?? DashboardQueryFilters.alertFilterDefaultOption),
           warning != required {
            return nil
        }

        let costTrend = weekStarts.map { recordByWeek[$0]?.costCents ?? 0 }
        let gsTrend = weekStarts.map { recordByWeek[$0]?.conversionValueCents ?? 0 }

        return ProductPerformanceRowMapper.map(
            product: product,
            sixWeekTotals: sixWeekTotals,
            totalCostCents: metricsContext.totalCostCents,
            overallBenchmark: metricsContext.overallBenchmark,
            weeklyCostTrend: costTrend,
            weeklyGSTrend: gsTrend,
            warningLabel: warning
        )
    }

    private func alertFilterLabel(for selection: String) -> ProductWarningLabel? {
        switch selection {
        case DashboardQueryFilters.alertFilterDefaultOption:
            nil
        default:
            ProductWarningLabel(rawValue: selection)
        }
    }

    private func parseCurrency(_ value: String) -> Double {
        let cleaned = value.replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0
    }
}
