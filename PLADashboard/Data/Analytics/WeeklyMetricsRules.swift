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
struct WeeklyCohortSpendBenchmark: Sendable, Hashable {
    let weekStart: String
    let medianDailyCents: Double
    let meanDailyCents: Double
}

enum ProductWarningLabel: String, Sendable, CaseIterable {
    // 三方站（消费 cohort 规则）
    case lowSpend = "低消费"
    case highSpendHighEfficiency = "高消高效"
    case highSpendLowEfficiency = "高消低效"
    case highSpend = "高消费"
    case lowEfficiency = "低效"

    // 自建站（标签引擎快照）
    case highEfficiency = "高效"
    case potentialNew = "潜力新品"
    case lowSampleOld = "低样本老品"
    case observation = "普通/观察"

    static let thirdPartyFilterCases: [ProductWarningLabel] = [
        .highSpendHighEfficiency,
        .highSpendLowEfficiency,
        .lowSpend,
        .highSpend,
        .lowEfficiency,
    ]

    static let selfBuiltFilterCases: [ProductWarningLabel] = [
        .highEfficiency,
        .potentialNew,
        .lowSampleOld,
        .lowEfficiency,
        .observation,
    ]
}

/// 看板预警标签解析引擎。
enum WarningLabelEngine: String, Sendable, Hashable {
    /// 三方站：近 6 周消费 cohort + 加权 ROI。
    case thirdPartyCohort
    /// 自建站：读取标签引擎周快照。
    case selfBuiltSnapshot

    static func forAccountKind(_ kind: WorkspaceAccountKind) -> WarningLabelEngine {
        switch kind {
        case .thirdParty: .thirdPartyCohort
        case .selfBuilt: .selfBuiltSnapshot
        }
    }
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

    static func cohortBenchmark(fromActiveProductWeeklyCostCents costs: [Int]) -> (medianDaily: Double, meanDaily: Double) {
        guard !costs.isEmpty else { return (0, 0) }
        let dailyCosts = costs.map { Double($0) / 7.0 }
        let sorted = dailyCosts.sorted()
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }
        let mean = dailyCosts.reduce(0, +) / Double(dailyCosts.count)
        return (median, mean)
    }

    static func lowSpendDailyThreshold(medianDailyCents: Double) -> Double {
        max(
            Double(AnalyticsConfiguration.lowSpendAbsoluteFloorDailyCents),
            AnalyticsConfiguration.lowSpendRatio * medianDailyCents
        )
    }

    static func resolveWarningLabel(
        productWeeks: [WeeklyProductMetrics],
        overallWeeks: [WeeklyProductMetrics],
        cohortBenchmarks: [WeeklyCohortSpendBenchmark],
        totalPortfolioCostCents: Int,
        settings: AnalyticsSettingsSnapshot = .defaults
    ) -> ProductWarningLabel? {
        let weights = AnalyticsConfiguration.roiWeekWeights
        guard productWeeks.count == weights.count,
              overallWeeks.count == weights.count,
              cohortBenchmarks.count == weights.count else {
            return nil
        }

        let productByWeek = Dictionary(uniqueKeysWithValues: productWeeks.map { ($0.weekStart, $0.metrics) })
        let overallByWeek = Dictionary(uniqueKeysWithValues: overallWeeks.map { ($0.weekStart, $0.metrics) })
        let cohortByWeek = Dictionary(uniqueKeysWithValues: cohortBenchmarks.map { ($0.weekStart, $0) })
        let weekStarts = productWeeks.map(\.weekStart)
        let recentWeeks = Array(weekStarts.suffix(AnalyticsConfiguration.consumptionLookbackWeeks))

        let isLowSpend = recentWeeks.allSatisfy { week in
            let productDaily = Double(productByWeek[week]?.costCents ?? 0) / 7.0
            let medianDaily = cohortByWeek[week]?.medianDailyCents ?? 0
            return productDaily < lowSpendDailyThreshold(medianDailyCents: medianDaily)
        }

        if isLowSpend {
            return .lowSpend
        }

        let productSixWeekCost = productWeeks.map(\.metrics).reduce(0) { $0 + $1.costCents }
        let meetsCostShare = totalPortfolioCostCents > 0
            && Double(productSixWeekCost) / Double(totalPortfolioCostCents)
                >= AnalyticsConfiguration.highSpendMinCostShare

        let isHighSpend = meetsCostShare && recentWeeks.allSatisfy { week in
            let productDaily = Double(productByWeek[week]?.costCents ?? 0) / 7.0
            let meanDaily = cohortByWeek[week]?.meanDailyCents ?? 0
            guard meanDaily > 0 else { return false }
            return productDaily > AnalyticsConfiguration.highSpendMeanRatio * meanDaily
        }

        let productMetrics = productWeeks.map(\.metrics)
        let overallMetrics = overallWeeks.map(\.metrics)
        let productWeightedROI = weightedROI(weeklyMetrics: productMetrics)
        let overallWeightedROI = weightedROI(weeklyMetrics: overallMetrics)

        let totalClicks = productMetrics.reduce(0) { $0 + $1.clicks }
        let totalConversions = productMetrics.reduce(0.0) { $0 + $1.conversions }
        let hasEfficiencySample = totalClicks >= AnalyticsConfiguration.efficiencyMinClicks
            && totalConversions >= AnalyticsConfiguration.efficiencyMinConversions

        let isHighEfficiency = hasEfficiencySample
            && recentWeeks.allSatisfy { week in
                (productByWeek[week]?.conversions ?? 0) >= 1
            }
            && productWeightedROI > settings.highEfficiencyROIMultiplier * overallWeightedROI

        let underperformWeekCount = recentWeeks.reduce(into: 0) { count, week in
            let productROI = productByWeek[week]?.roi ?? 0
            let overallROI = overallByWeek[week]?.roi ?? 0
            if productROI < overallROI {
                count += 1
            }
        }
        let isLowEfficiency = hasEfficiencySample
            && productWeightedROI < overallWeightedROI
            && underperformWeekCount >= AnalyticsConfiguration.lowEfficiencyWeeklyUnderperformWeeks
            && totalClicks > settings.lowEfficiencyMinClicks

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
