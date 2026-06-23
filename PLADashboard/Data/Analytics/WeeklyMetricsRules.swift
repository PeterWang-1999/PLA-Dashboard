import Foundation

struct AggregatedMetrics: Sendable, Hashable {
    var costCents: Int = 0
    var impressions: Int = 0
    var clicks: Int = 0
    var conversions: Double = 0
    var conversionValueCents: Int = 0
    var grossSalesCents: Int = 0

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
            grossSalesCents: lhs.grossSalesCents + rhs.grossSalesCents
        )
    }
}

struct WeeklyProductMetrics: Sendable, Hashable {
    let productId: String
    let weekStart: String
    let metrics: AggregatedMetrics
}

enum ProductWarningLabel: String, Sendable, CaseIterable {
    case lowSpend = "低消费"
    case highSpendHighEfficiency = "高消高效"
    case highSpendLowEfficiency = "高消低效"
    case highSpend = "高消费"
    case lowEfficiency = "低效"
}

enum WeeklyMetricsRules {
    static func weightedROI(
        weeklyMetrics: [AggregatedMetrics],
        weights: [Double] = AnalyticsConfiguration.roiWeekWeights
    ) -> Double {
        guard weeklyMetrics.count == weights.count else { return 0 }
        return zip(weeklyMetrics, weights).reduce(0) { partial, pair in
            partial + pair.0.roi * pair.1
        }
    }

    static func relativeDelta(product: Double, overall: Double) -> Double? {
        guard overall != 0 else { return nil }
        return product / overall - 1
    }

    static func resolveWarningLabel(
        productWeeks: [WeeklyProductMetrics],
        overallWeeks: [WeeklyProductMetrics],
        config: AnalyticsConfiguration.Type = AnalyticsConfiguration.self
    ) -> ProductWarningLabel? {
        _ = config
        let weights = AnalyticsConfiguration.roiWeekWeights
        guard productWeeks.count == weights.count, overallWeeks.count == weights.count else {
            return nil
        }

        let productByWeek = Dictionary(uniqueKeysWithValues: productWeeks.map { ($0.weekStart, $0.metrics) })
        let overallByWeek = Dictionary(uniqueKeysWithValues: overallWeeks.map { ($0.weekStart, $0.metrics) })
        let weekStarts = productWeeks.map(\.weekStart)
        let recentWeeks = Array(weekStarts.suffix(AnalyticsConfiguration.consumptionLookbackWeeks))

        let isLowSpend = recentWeeks.allSatisfy { week in
            let productDaily = Double(productByWeek[week]?.costCents ?? 0) / 7.0
            let overallDaily = Double(overallByWeek[week]?.costCents ?? 0) / 7.0
            return productDaily < overallDaily
        }

        if isLowSpend {
            return .lowSpend
        }

        let isHighSpend = recentWeeks.allSatisfy { week in
            let productDaily = Double(productByWeek[week]?.costCents ?? 0) / 7.0
            let overallDaily = Double(overallByWeek[week]?.costCents ?? 0) / 7.0
            guard overallDaily > 0 else { return false }
            return productDaily > AnalyticsConfiguration.highSpendDailyMultiplier * overallDaily
        }

        let productMetrics = productWeeks.map(\.metrics)
        let overallMetrics = overallWeeks.map(\.metrics)
        let productWeightedROI = weightedROI(weeklyMetrics: productMetrics)
        let overallWeightedROI = weightedROI(weeklyMetrics: overallMetrics)

        let isHighEfficiency = recentWeeks.allSatisfy { week in
            let metrics = productByWeek[week] ?? AggregatedMetrics()
            return metrics.roi != 0
        } && productWeightedROI > AnalyticsConfiguration.highEfficiencyROIMultiplier * overallWeightedROI

        let totalClicks = productMetrics.reduce(0) { $0 + $1.clicks }
        let isLowEfficiency = productWeightedROI < overallWeightedROI
            && recentWeeks.allSatisfy { week in
                let productROI = productByWeek[week]?.roi ?? 0
                let overallROI = overallByWeek[week]?.roi ?? 0
                return productROI < overallROI
            }
            && totalClicks > AnalyticsConfiguration.lowEfficiencyMinClicks

        if isHighSpend && isHighEfficiency {
            return .highSpendHighEfficiency
        }
        if isHighSpend && isLowEfficiency {
            return .highSpendLowEfficiency
        }
        if isHighSpend {
            return .highSpend
        }
        if isLowEfficiency {
            return .lowEfficiency
        }
        return nil
    }
}
