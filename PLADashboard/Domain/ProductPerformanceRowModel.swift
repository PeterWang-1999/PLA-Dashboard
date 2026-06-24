import SwiftUI

struct ProductPerformanceRowModel: Identifiable, Hashable, Sendable {
    let id: String
    let lsin: String
    let imageURL: URL?
    let cost: String
    let costShare: String
    let roi: String
    let warningLabel: String
    let warningStyle: WarningLabelStyle
    let cpa: String
    let cpaDelta: String
    let arpu: String
    let arpuDelta: String
    let cpc: String
    let cpcDelta: String
    let cvr: String
    let cvrDelta: String
    let aos: String
    let aosDelta: String
    let clicks: String?
    let conversions: String?
    let costTrendWeeks: [Int]
    let gsTrendWeeks: [Int]
    let sortCostCents: Int
    let sortROI: Double
    let sortClicks: Int
    let sortLSIN: String

    var accessibilitySummary: String {
        "产品 \(lsin)，消费 \(cost)，投资回报率 \(roi)，预警 \(warningLabel)"
    }

    enum WarningLabelStyle: String, Hashable, Sendable {
        case none
        case lowSpend
        case highSpendHighEfficiency
        case highSpendLowEfficiency
        case highSpend
        case lowEfficiency
    }
}

enum DashboardDataSource: Sendable {
    case preview
    case empty
    case database
}
