import Foundation
import GRDB

extension DatabaseClient {
    /// 从周聚合表与产品维表构建标签指标（单次读库，内存计算）。
    func buildLabelMetrics(weekStarts: [String]) throws -> LabelMetricsResult {
        guard weekStarts.count == LabelEngineConstants.reportingWeekCount else {
            throw LabelMetricsBuilderError.invalidWeekCount(weekStarts.count)
        }

        let (facts, metas) = try dbQueue.read { db -> ([LabelWeeklyFact], [LabelProductMeta]) in
            let weekPlaceholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            let metricsSQL = """
                SELECT product_id, week_start, cost_cents, impressions, clicks, conversions,
                       conversion_value_cents, gross_sales_cents, gross_profit_cents
                FROM product_weekly_metrics
                WHERE week_start IN (\(weekPlaceholders));
                """
            var weekArgs = StatementArguments()
            for week in weekStarts { weekArgs += [week] }

            let metricRows = try Row.fetchAll(db, sql: metricsSQL, arguments: weekArgs)
            var facts: [LabelWeeklyFact] = []
            facts.reserveCapacity(metricRows.count)
            var productIDs = Set<String>()
            productIDs.reserveCapacity(metricRows.count)

            for row in metricRows {
                guard let productId: String = row["product_id"],
                      let weekStart: String = row["week_start"] else {
                    continue
                }
                productIDs.insert(productId)
                facts.append(LabelWeeklyFact(
                    productId: productId,
                    weekStart: weekStart,
                    costCents: row["cost_cents"] ?? 0,
                    impressions: row["impressions"] ?? 0,
                    clicks: row["clicks"] ?? 0,
                    conversions: row["conversions"] ?? 0,
                    conversionValueCents: row["conversion_value_cents"] ?? 0,
                    grossSalesCents: row["gross_sales_cents"] ?? 0,
                    grossProfitCents: row["gross_profit_cents"] ?? 0
                ))
            }

            guard !productIDs.isEmpty else {
                return ([], [])
            }

            let idList = Array(productIDs)
            let idPlaceholders = Array(repeating: "?", count: idList.count).joined(separator: ", ")
            let productSQL = """
                SELECT product_id, first_listed_at, google_product_category, pla_cms3
                FROM products
                WHERE product_id IN (\(idPlaceholders));
                """
            var idArgs = StatementArguments()
            for id in idList { idArgs += [id] }
            let productRows = try Row.fetchAll(db, sql: productSQL, arguments: idArgs)

            var metaByID: [String: LabelProductMeta] = [:]
            metaByID.reserveCapacity(productRows.count)
            for row in productRows {
                guard let productId: String = row["product_id"] else { continue }
                let plaCMS3 = (row["pla_cms3"] as String?)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cms3: String
                if let plaCMS3, !plaCMS3.isEmpty {
                    cms3 = plaCMS3
                } else {
                    let category: String? = row["google_product_category"]
                    cms3 = ProductCategoryPath.cms3Leaf(fromStored: category)
                }
                metaByID[productId] = LabelProductMeta(
                    productId: productId,
                    firstListedAt: row["first_listed_at"],
                    cms3: cms3
                )
            }

            // 周表有、产品表无的 ID：仍参与计算，CMS3=未分类
            let metas = idList.map { id in
                metaByID[id] ?? LabelProductMeta(
                    productId: id,
                    firstListedAt: nil,
                    cms3: LabelEngineConstants.unclassifiedCMS3
                )
            }
            return (facts, metas)
        }

        return try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: metas
        )
    }
}
