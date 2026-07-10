import Foundation
import GRDB

struct ProductWeeklyMetricsRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "product_weekly_metrics"

    var productId: String
    var weekStart: String
    var costCents: Int
    var impressions: Int
    var clicks: Int
    var conversions: Double
    var conversionValueCents: Int
    var grossSalesCents: Int
    var grossProfitCents: Int
    var roi: Double?
    var cpaCents: Int?
    var cpcCents: Int?
    var cvr: Double?
    var aos: Double?
    var warningLabel: String?

    enum Columns: String, ColumnExpression {
        case productId = "product_id"
        case weekStart = "week_start"
        case costCents = "cost_cents"
        case impressions
        case clicks
        case conversions
        case conversionValueCents = "conversion_value_cents"
        case grossSalesCents = "gross_sales_cents"
        case grossProfitCents = "gross_profit_cents"
        case roi
        case cpaCents = "cpa_cents"
        case cpcCents = "cpc_cents"
        case cvr
        case aos
        case warningLabel = "warning_label"
    }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case weekStart = "week_start"
        case costCents = "cost_cents"
        case impressions
        case clicks
        case conversions
        case conversionValueCents = "conversion_value_cents"
        case grossSalesCents = "gross_sales_cents"
        case grossProfitCents = "gross_profit_cents"
        case roi
        case cpaCents = "cpa_cents"
        case cpcCents = "cpc_cents"
        case cvr
        case aos
        case warningLabel = "warning_label"
    }

    var aggregatedMetrics: AggregatedMetrics {
        AggregatedMetrics(
            costCents: costCents,
            impressions: impressions,
            clicks: clicks,
            conversions: conversions,
            conversionValueCents: conversionValueCents,
            grossSalesCents: grossSalesCents,
            grossProfitCents: grossProfitCents
        )
    }

    static func make(
        productId: String,
        weekStart: String,
        metrics: AggregatedMetrics
    ) -> ProductWeeklyMetricsRecord {
        let roi = metrics.roi
        let cpaCents = metrics.conversions > 0
            ? Int((Double(metrics.costCents) / metrics.conversions).rounded())
            : nil
        let cpcCents = metrics.clicks > 0
            ? metrics.costCents / metrics.clicks
            : nil
        let cvr = metrics.clicks > 0 ? metrics.cvr : nil
        let aos = metrics.conversions > 0 ? metrics.aos : nil

        return ProductWeeklyMetricsRecord(
            productId: productId,
            weekStart: weekStart,
            costCents: metrics.costCents,
            impressions: metrics.impressions,
            clicks: metrics.clicks,
            conversions: metrics.conversions,
            conversionValueCents: metrics.conversionValueCents,
            grossSalesCents: metrics.grossSalesCents,
            grossProfitCents: metrics.grossProfitCents,
            roi: roi,
            cpaCents: cpaCents,
            cpcCents: cpcCents,
            cvr: cvr,
            aos: aos,
            warningLabel: nil
        )
    }
}
