import Foundation

enum DashboardTableSort: String, Sendable, Hashable, CaseIterable {
    case costDescending
    case costAscending
    case roiDescending
    case roiAscending
    case clicksDescending
    case clicksAscending
    case lsinAscending

    static let `default` = DashboardTableSort.costDescending

    var sqlOrderClause: String {
        switch self {
        case .costDescending:
            "SUM(m.cost_cents) DESC, p.product_id ASC"
        case .costAscending:
            "SUM(m.cost_cents) ASC, p.product_id ASC"
        case .roiDescending:
            """
            CASE WHEN SUM(m.cost_cents) > 0
              THEN CAST(SUM(m.conversion_value_cents) AS REAL) / SUM(m.cost_cents)
              ELSE 0 END DESC, p.product_id ASC
            """
        case .roiAscending:
            """
            CASE WHEN SUM(m.cost_cents) > 0
              THEN CAST(SUM(m.conversion_value_cents) AS REAL) / SUM(m.cost_cents)
              ELSE 0 END ASC, p.product_id ASC
            """
        case .clicksDescending:
            "SUM(m.clicks) DESC, p.product_id ASC"
        case .clicksAscending:
            "SUM(m.clicks) ASC, p.product_id ASC"
        case .lsinAscending:
            "COALESCE(p.lsin, p.product_id) ASC, p.product_id ASC"
        }
    }

    var menuTitle: String {
        switch self {
        case .costDescending: "消费（高→低）"
        case .costAscending: "消费（低→高）"
        case .roiDescending: "ROI（高→低）"
        case .roiAscending: "ROI（低→高）"
        case .clicksDescending: "点击（高→低）"
        case .clicksAscending: "点击（低→高）"
        case .lsinAscending: "产品 ID（A→Z）"
        }
    }

    static let toolbarOptions: [DashboardTableSort] = [
        .costDescending,
        .costAscending,
        .roiDescending,
        .roiAscending,
        .clicksDescending,
        .clicksAscending,
        .lsinAscending,
    ]
}
