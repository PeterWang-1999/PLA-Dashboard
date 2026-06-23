import Foundation

struct DashboardQueryFilters: Sendable, Hashable {
    static let alertFilterDefaultOption = "全部预警标签"

    var searchText: String = ""
    var alertFilter: String = Self.alertFilterDefaultOption
    var customLabelFilter: CustomLabelFilterSelection = .all
    var categoryFilter: CategoryFilterSelection = .all
}

struct DashboardPageResult: Sendable {
    let rows: [ProductPerformanceRowModel]
    let totalCount: Int
    let totalPages: Int
}

enum DashboardMetricFormatter {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.multiplier = 1
        return formatter
    }()

    static func formatInteger(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatCurrencyFromCents(_ cents: Int) -> String {
        let amount = Double(cents) / 100
        return decimalFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    static func formatDecimal(_ value: Double, fractionDigits: Int = 2) -> String {
        decimalFormatter.minimumFractionDigits = fractionDigits
        decimalFormatter.maximumFractionDigits = fractionDigits
        return decimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }

    static func formatPercentValue(_ ratio: Double) -> String {
        formatDecimal(ratio * 100, fractionDigits: 2) + "%"
    }

    static func formatSharePercent(costCents: Int, totalCostCents: Int) -> String {
        guard totalCostCents > 0 else { return "—" }
        let share = Double(costCents) / Double(totalCostCents) * 100
        return formatDecimal(share, fractionDigits: 2) + "%"
    }

    static func formatRelativeDelta(product: Double, overall: Double) -> String {
        guard let delta = WeeklyMetricsRules.relativeDelta(product: product, overall: overall) else {
            return "—"
        }
        let percent = delta * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(formatDecimal(percent, fractionDigits: 0))%"
    }
}

enum ProductPerformanceRowMapper {
    static func map(
        product: ProductRecord,
        sixWeekTotals: AggregatedMetrics,
        totalCostCents: Int,
        overallBenchmark: AggregatedMetrics,
        weeklyCostTrend: [Int],
        weeklyGSTrend: [Int],
        warningLabel: ProductWarningLabel?
    ) -> ProductPerformanceRowModel {
        let displayLSIN = product.lsin ?? product.productId

        return ProductPerformanceRowModel(
            id: product.productId,
            lsin: displayLSIN,
            imageURL: product.imageUrl.flatMap(URL.init(string:)),
            cost: DashboardMetricFormatter.formatCurrencyFromCents(sixWeekTotals.costCents),
            costShare: DashboardMetricFormatter.formatSharePercent(
                costCents: sixWeekTotals.costCents,
                totalCostCents: totalCostCents
            ),
            roi: DashboardMetricFormatter.formatDecimal(sixWeekTotals.roi, fractionDigits: 2),
            warningLabel: warningLabel?.rawValue ?? "—",
            warningStyle: warningStyle(for: warningLabel),
            cpa: DashboardMetricFormatter.formatDecimal(sixWeekTotals.cpa),
            cpaDelta: DashboardMetricFormatter.formatRelativeDelta(
                product: sixWeekTotals.cpa,
                overall: overallBenchmark.cpa
            ),
            arpu: DashboardMetricFormatter.formatDecimal(sixWeekTotals.arpu),
            arpuDelta: DashboardMetricFormatter.formatRelativeDelta(
                product: sixWeekTotals.arpu,
                overall: overallBenchmark.arpu
            ),
            cpc: DashboardMetricFormatter.formatDecimal(sixWeekTotals.cpc),
            cpcDelta: DashboardMetricFormatter.formatRelativeDelta(
                product: sixWeekTotals.cpc,
                overall: overallBenchmark.cpc
            ),
            cvr: DashboardMetricFormatter.formatPercentValue(sixWeekTotals.cvr),
            cvrDelta: DashboardMetricFormatter.formatRelativeDelta(
                product: sixWeekTotals.cvr,
                overall: overallBenchmark.cvr
            ),
            aos: DashboardMetricFormatter.formatDecimal(sixWeekTotals.aos),
            aosDelta: DashboardMetricFormatter.formatRelativeDelta(
                product: sixWeekTotals.aos,
                overall: overallBenchmark.aos
            ),
            clicks: DashboardMetricFormatter.formatInteger(sixWeekTotals.clicks),
            conversions: DashboardMetricFormatter.formatDecimal(sixWeekTotals.conversions, fractionDigits: 0),
            costTrendWeeks: weeklyCostTrend,
            gsTrendWeeks: weeklyGSTrend
        )
    }

    private static func warningStyle(for label: ProductWarningLabel?) -> ProductPerformanceRowModel.WarningLabelStyle {
        switch label {
        case .lowSpend:
            .lowSpend
        case .highSpendHighEfficiency:
            .highSpendHighEfficiency
        case .highSpendLowEfficiency:
            .highSpendLowEfficiency
        case .highSpend:
            .highSpend
        case .lowEfficiency:
            .lowEfficiency
        case nil:
            .none
        }
    }
}
