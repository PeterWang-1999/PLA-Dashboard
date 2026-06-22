import Foundation

enum DashboardColumn: String, CaseIterable, Identifiable {
    case lsin = "LSIN"
    case productImage = "产品图"
    case cost = "消费"
    case roi = "ROI"
    case warningLabel = "预警标签"
    case costTrend = "消费趋势"
    case gsTrend = "GS 趋势"
    case cpa = "CPA"
    case arpu = "ARPU"
    case cpc = "CPC"
    case cvr = "CVR"
    case aos = "AOS"
    case clicks = "点击次数"
    case conversions = "转化次数"

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .lsin: 68
        case .productImage: 48
        case .cost: 56
        case .roi: 40
        case .warningLabel: 72
        case .costTrend, .gsTrend: 56
        case .cpa, .arpu, .cpc, .aos: 44
        case .cvr: 52
        case .clicks, .conversions: 56
        }
    }
}

enum DashboardColumnLayout {
    static let sidebarExpanded: [DashboardColumn] = [
        .lsin, .productImage, .cost, .roi, .warningLabel,
        .costTrend, .gsTrend, .cpa, .arpu, .cpc, .cvr, .aos,
    ]

    static let sidebarCollapsed: [DashboardColumn] = sidebarExpanded + [.clicks, .conversions]

    static func visibleColumns(isSidebarVisible: Bool) -> [DashboardColumn] {
        isSidebarVisible ? sidebarExpanded : sidebarCollapsed
    }
}
