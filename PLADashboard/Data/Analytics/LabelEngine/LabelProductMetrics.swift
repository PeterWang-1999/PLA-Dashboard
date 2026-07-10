import Foundation

/// 单产品 × 单周事实（金额为分，与 `product_weekly_metrics` 一致）。
struct LabelWeeklyFact: Sendable, Hashable {
    var productId: String
    var weekStart: String
    var costCents: Int
    var impressions: Int
    var clicks: Int
    var conversions: Double
    var conversionValueCents: Int
    var grossSalesCents: Int
    var grossProfitCents: Int
}

/// 产品维表字段（CMS3 优先 PLA 列，否则 Merchant 类目末级）。
struct LabelProductMeta: Sendable, Hashable {
    var productId: String
    var firstListedAt: String?
    var cms3: String
}

/// 单产品标签指标行（对标 Python `agg`）。
struct LabelProductMetricsRow: Sendable, Hashable {
    var productId: String
    var primaryCMS3: String
    var firstListedAt: String?

    var cost6wCents: Int
    var impressions6w: Int
    var clicks6w: Int
    var conversions6w: Double
    var conversionValue6wCents: Int
    var grossSales6wCents: Int
    var grossProfit6wCents: Int
    var weeksWithData: Int

    var weightedCostCents: Double
    var weightedConversionValueCents: Double
    var weightedGrossSalesCents: Double
    var weightedGrossProfitCents: Double

    var weightedAdROI: Double?
    var weightedMarginReturn: Double?
    var realizedMarginRate: Double?

    var activeWeeksRecent3: Int
    var activeCurrentWeek: Bool
    var noConvGSCurrentWeek: Bool

    var isNewByFirstListed3m: Bool
    var dataNormal: Bool

    var categorySampleSufficient: Bool
    var categoryBenchmarkROI: Double?
    var categoryInsufficientReason: String
    var benchmarkSource: String
    var appliedBenchmarkROI: Double?
}

struct LabelCategoryBenchmark: Sendable, Hashable {
    var cms3: String
    var cost6wCents: Int
    var clicks6w: Int
    var conversions6w: Double
    var conversionValue6wCents: Int
    var spendProducts6w: Int
    var products6w: Int
    var weightedCostCents: Double
    var weightedConversionValueCents: Double
    var benchmarkROI: Double?
    var sampleSufficient: Bool
    var insufficientReason: String
}

struct LabelMetricsThresholds: Sendable, Hashable {
    var highMarginThreshold: Double
    var matureMarginP50: Double?
    var matureSampleN: Int
    var newGSP50Cents: Double?
    var newGSP75Cents: Double?
    var newPositiveN: Int
    var oldGSP50Cents: Double?
    var oldPositiveN: Int
    var newCutoffDay: String
    var siteBenchmarkROI: Double?
}

struct LabelMetricsResult: Sendable {
    var weekStarts: [String]
    var currentWeekStart: String
    var products: [LabelProductMetricsRow]
    var categories: [LabelCategoryBenchmark]
    var thresholds: LabelMetricsThresholds
}
