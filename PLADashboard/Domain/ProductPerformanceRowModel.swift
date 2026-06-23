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
