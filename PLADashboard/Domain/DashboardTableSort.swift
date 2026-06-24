import Foundation
import SwiftUI

enum DashboardTableSort: String, Sendable, Hashable, CaseIterable {
    case costDescending
    case costAscending
    case roiDescending
    case roiAscending

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
        }
    }

    var columnSortOrder: [KeyPathComparator<ProductPerformanceRowModel>] {
        switch self {
        case .costDescending:
            [KeyPathComparator(\.sortCostCents, order: .reverse)]
        case .costAscending:
            [KeyPathComparator(\.sortCostCents, order: .forward)]
        case .roiDescending:
            [KeyPathComparator(\.sortROI, order: .reverse)]
        case .roiAscending:
            [KeyPathComparator(\.sortROI, order: .forward)]
        }
    }

    static func from(columnSortOrder: [KeyPathComparator<ProductPerformanceRowModel>]) -> DashboardTableSort? {
        guard let comparator = columnSortOrder.first else { return nil }

        switch comparator.keyPath {
        case \ProductPerformanceRowModel.sortCostCents:
            return comparator.order == .forward ? .costAscending : .costDescending
        case \ProductPerformanceRowModel.sortROI:
            return comparator.order == .forward ? .roiAscending : .roiDescending
        default:
            return nil
        }
    }

    func sortsBefore(_ lhs: ProductPerformanceRowModel, _ rhs: ProductPerformanceRowModel) -> Bool {
        switch self {
        case .costDescending:
            lhs.sortCostCents > rhs.sortCostCents
        case .costAscending:
            lhs.sortCostCents < rhs.sortCostCents
        case .roiDescending:
            lhs.sortROI > rhs.sortROI
        case .roiAscending:
            lhs.sortROI < rhs.sortROI
        }
    }
}
