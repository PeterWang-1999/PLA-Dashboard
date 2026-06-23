import Foundation

enum DashboardColumn: String, CaseIterable, Identifiable {
    case lsin = "产品 ID"
    case productImage = "产品图"
    case cost = "消费"
    case roi = "ROI"
    case warningLabel = "预警标签"
    case costTrend = "消费趋势"
    case gsTrend = "销售趋势"
    case cpa = "CPA"
    case arpu = "ARPU"
    case cpc = "CPC"
    case cvr = "CVR"
    case aos = "AOS"
    case clicks = "点击次数"
    case conversions = "转化次数"

    var id: String { rawValue }

    /// `TableColumn.width(min:ideal:max:)` 布局规格。
    struct WidthSpec {
        let min: CGFloat
        let ideal: CGFloat
        let max: CGFloat

        static func fixed(min: CGFloat, ideal: CGFloat) -> WidthSpec {
            WidthSpec(min: min, ideal: ideal, max: ideal)
        }

        static func flexible(min: CGFloat, ideal: CGFloat) -> WidthSpec {
            WidthSpec(min: min, ideal: ideal, max: .infinity)
        }
    }

    var widthSpec: WidthSpec {
        switch self {
        case .lsin:
            .fixed(min: 110, ideal: 115)
        case .productImage:
            .fixed(min: 40, ideal: 45)
        case .cost:
            .fixed(min: 56, ideal: 72)
        case .roi:
            .fixed(min: 40, ideal: 52)
        case .warningLabel:
            .fixed(min: 72, ideal: 88)
        case .costTrend, .gsTrend:
            .flexible(min: 50, ideal: 65)
        case .cpa, .arpu, .cpc, .aos:
            .flexible(min: 40, ideal: 60)
        case .cvr:
            .flexible(min: 50, ideal: 65)
        case .clicks, .conversions:
            .fixed(min: 55, ideal: 70)
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
