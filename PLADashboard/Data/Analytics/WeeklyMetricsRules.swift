import Foundation

struct AggregatedMetrics: Sendable, Hashable {
    var costCents: Int = 0
    var impressions: Int = 0
    var clicks: Int = 0
    var conversions: Double = 0
    var conversionValueCents: Int = 0
    var grossSalesCents: Int = 0
    var grossProfitCents: Int = 0

    var roi: Double {
        guard costCents > 0 else { return 0 }
        return Double(conversionValueCents) / Double(costCents)
    }

    var cpa: Double {
        guard conversions > 0 else { return 0 }
        return Double(costCents) / conversions / 100
    }

    var cpc: Double {
        guard clicks > 0 else { return 0 }
        return Double(costCents) / Double(clicks) / 100
    }

    var cvr: Double {
        guard clicks > 0 else { return 0 }
        return conversions / Double(clicks)
    }

    var aos: Double {
        guard conversions > 0 else { return 0 }
        return Double(conversionValueCents) / conversions / 100
    }

    var arpu: Double {
        cvr * aos
    }

    static func + (lhs: AggregatedMetrics, rhs: AggregatedMetrics) -> AggregatedMetrics {
        AggregatedMetrics(
            costCents: lhs.costCents + rhs.costCents,
            impressions: lhs.impressions + rhs.impressions,
            clicks: lhs.clicks + rhs.clicks,
            conversions: lhs.conversions + rhs.conversions,
            conversionValueCents: lhs.conversionValueCents + rhs.conversionValueCents,
            grossSalesCents: lhs.grossSalesCents + rhs.grossSalesCents,
            grossProfitCents: lhs.grossProfitCents + rhs.grossProfitCents
        )
    }
}

struct WeeklyProductMetrics: Sendable, Hashable {
    let productId: String
    let weekStart: String
    let metrics: AggregatedMetrics
}

/// 当周有消费 SKU 的日均消费 cohort 基准（中位数用于低消、均值用于高消）。
enum WeeklyMetricsRules {
    static func relativeDelta(product: Double, overall: Double) -> Double? {
        guard overall != 0 else { return nil }
        return product / overall - 1
    }
}
