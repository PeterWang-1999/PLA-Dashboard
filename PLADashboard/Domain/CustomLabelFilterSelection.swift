import Foundation

/// 自定义标签筛选：默认「全部自定义标签」，或选中列 / 列内具体值。
enum CustomLabelFilterSelection: Hashable, Codable {
    case all
    case column(String)
    case value(column: String, value: String)

    static let defaultTitle = "全部自定义标签"

    var menuTitle: String {
        switch self {
        case .all:
            Self.defaultTitle
        case .column(let column):
            column
        case .value(_, let value):
            value
        }
    }

    var isFiltered: Bool {
        self != .all
    }

    /// 用于后续 SQL / FTS 筛选（阶段 2 接入）。
    var filterColumn: String? {
        switch self {
        case .all:
            nil
        case .column(let column), .value(let column, _):
            column
        }
    }

    var filterValue: String? {
        switch self {
        case .all, .column:
            nil
        case .value(_, let value):
            value
        }
    }
}
