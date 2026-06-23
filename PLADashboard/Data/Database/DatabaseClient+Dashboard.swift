import Foundation
import GRDB

extension DatabaseClient {
    func searchProductIDs(query: String, limit: Int = 500) throws -> [String] {
        try dbQueue.read { db in
            try searchProductIDs(query: query, limit: limit, db: db)
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
        let latestDay = try fetchLatestMetricDay()
        guard let latestDay, let endDate = WeekCalendar.parseDay(latestDay) else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        let weekStarts = WeekCalendar.reportingWeekStarts(endingAt: endDate)
        guard !weekStarts.isEmpty else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        let overallWeeks = try fetchOverallWeeklyMetrics(weekStarts: weekStarts)
        let cohortBenchmarks = try fetchWeeklyCohortSpendBenchmarks(weekStarts: weekStarts)
        let overallBenchmark = overallWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
        let totalCostCents = overallBenchmark.costCents

        let candidateProducts = try fetchFilteredProducts(dbQueue: dbQueue, filters: filters, weekStarts: weekStarts)
        guard !candidateProducts.isEmpty else {
            return DashboardPageResult(rows: [], totalCount: 0, totalPages: 1)
        }

        let productIds = candidateProducts.map(\.productId)
        let weeklyRecords = try fetchWeeklyMetrics(productIds: productIds, weekStarts: weekStarts)
        let weeklyByProduct = Dictionary(grouping: weeklyRecords, by: \.productId)

        var mappedRows: [ProductPerformanceRowModel] = []
        mappedRows.reserveCapacity(candidateProducts.count)

        for product in candidateProducts {
            let records = weeklyByProduct[product.productId] ?? []
            let recordByWeek = Dictionary(uniqueKeysWithValues: records.map { ($0.weekStart, $0) })

            let productWeeks: [WeeklyProductMetrics] = weekStarts.map { week in
                let metrics = recordByWeek[week]?.aggregatedMetrics ?? AggregatedMetrics()
                return WeeklyProductMetrics(productId: product.productId, weekStart: week, metrics: metrics)
            }

            let sixWeekTotals = productWeeks.map(\.metrics).reduce(AggregatedMetrics()) { $0 + $1 }
            guard sixWeekTotals.costCents > 0 || sixWeekTotals.grossSalesCents > 0 else { continue }

            let warning = WeeklyMetricsRules.resolveWarningLabel(
                productWeeks: productWeeks,
                overallWeeks: overallWeeks,
                cohortBenchmarks: cohortBenchmarks,
                totalPortfolioCostCents: totalCostCents
            )

            if let required = alertFilterLabel(for: filters.alertFilter),
               warning != required {
                continue
            }

            let costTrend = weekStarts.map { recordByWeek[$0]?.costCents ?? 0 }
            let gsTrend = weekStarts.map { recordByWeek[$0]?.grossSalesCents ?? 0 }

            mappedRows.append(ProductPerformanceRowMapper.map(
                product: product,
                sixWeekTotals: sixWeekTotals,
                totalCostCents: totalCostCents,
                overallBenchmark: overallBenchmark,
                weeklyCostTrend: costTrend,
                weeklyGSTrend: gsTrend,
                warningLabel: warning
            ))
        }

        mappedRows.sort { lhs, rhs in
            parseCurrency(lhs.cost) > parseCurrency(rhs.cost)
        }

        let totalCount = mappedRows.count
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        let safePage = min(max(page, 1), totalPages)
        let start = (safePage - 1) * pageSize
        let end = min(start + pageSize, totalCount)
        let pageRows = start < end ? Array(mappedRows[start..<end]) : []

        return DashboardPageResult(rows: pageRows, totalCount: totalCount, totalPages: totalPages)
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

    private func fetchFilteredProducts(
        dbQueue: DatabaseQueue,
        filters: DashboardQueryFilters,
        weekStarts: [String]
    ) throws -> [ProductRecord] {
        try dbQueue.read { db in
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            var sql = """
                SELECT DISTINCT p.*
                FROM products p
                INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
                WHERE m.week_start IN (\(weekPlaceholders))
                """
            var arguments = StatementArguments()
            for week in weekStarts { arguments += [week] }

            let search = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !search.isEmpty {
                let searchIDs = try searchProductIDs(query: search, limit: 500, db: db)
                if searchIDs.isEmpty {
                    return []
                }
                let placeholders = Array(repeating: "?", count: searchIDs.count).joined(separator: ", ")
                sql += " AND p.product_id IN (\(placeholders))"
                for id in searchIDs { arguments += [id] }
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

            sql += " ORDER BY p.product_id ASC;"

            return try ProductRecord.fetchAll(db, sql: sql, arguments: arguments)
        }
    }
}
