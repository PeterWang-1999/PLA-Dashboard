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
    /// 趋势周（周日起算），与两个趋势数组逐项对应；通常为 6 个完整周 + 当前周。
    let trendWeekStarts: [String]
    /// 每个趋势周实际覆盖的自然日数；完整周为 7，当前周按最新数据日计算。
    let trendCoverageDays: [Int]
    let sortCostCents: Int
    let sortROI: Double
    let sortClicks: Int
    let sortLSIN: String

    enum WarningLabelStyle: String, Hashable, Sendable {
        case none
        case lowSpend
        case highSpendHighEfficiency
        case highSpendLowEfficiency
        case highSpend
        case lowEfficiency
        case highEfficiency
        case potentialNew
        case lowSampleOld
        case observation
    }
}

enum DashboardDataSource: Sendable {
    case preview
    case empty
    case database
}
