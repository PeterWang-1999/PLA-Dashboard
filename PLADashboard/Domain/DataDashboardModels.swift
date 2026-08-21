import Foundation

struct DataDashboardSnapshot: Sendable {
    var metrics: [DataDashboardMetric] = []
    var weeklyTrend: [DataDashboardTrendPoint] = []
    var dailyTrend: [DataDashboardTrendPoint] = []
    var campaigns: [DataDashboardCampaignRow] = []
    var categories: [DataDashboardCategoryPoint] = []
    var topProducts: [DataDashboardProduct] = []
    var reportingPeriodLabel: String?

    static let empty = DataDashboardSnapshot()
}

struct DataDashboardMetric: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case spend, sales, roi, cvr, cpc, aos
    }

    let kind: Kind
    let title: String
    let value: String
    let reference: String
    let comparisonLabel: String
    let comparison: String
    let comparisonDirection: ComparisonDirection

    var id: Kind { kind }
}

enum ComparisonDirection: Sendable {
    case positive, negative, neutral
}

struct DataDashboardTrendPoint: Identifiable, Sendable {
    let period: String
    let displayLabel: String
    let costCents: Int
    let salesCents: Int
    let roi: Double

    var id: String { period }
}

struct DataDashboardCampaignRow: Identifiable, Sendable {
    let campaign: String
    let metrics: AggregatedMetrics

    var id: String { campaign }
}

struct DataDashboardCategoryPoint: Identifiable, Sendable {
    let category: String
    let metrics: AggregatedMetrics

    var id: String { category }
}

struct DataDashboardProduct: Identifiable, Sendable {
    let productID: String
    let title: String
    let imageURL: URL?
    let metrics: AggregatedMetrics

    var id: String { productID }
}
