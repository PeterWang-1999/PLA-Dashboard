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

    /// Merchant TSV 列名（如「自定义标签 0」），供 UI 与 catalog 使用。
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

    /// TSV 列名 → `products` 表 SQL 列名（白名单）。
    static let sqlColumnByDisplayName: [String: String] = Dictionary(
        uniqueKeysWithValues: CustomLabelCatalog.columnNames.enumerated().map { index, name in
            (name, "custom_label_\(index)")
        }
    )

    /// 解析后的 SQL 列名；未知列名返回 `nil`。
    var sqlColumnName: String? {
        guard let displayName = filterColumn else { return nil }
        return Self.sqlColumnByDisplayName[displayName]
    }

    enum SQLClause: Equatable {
        case none
        case columnNotEmpty(column: String)
        case equals(column: String, value: String)
    }

    var sqlClause: SQLClause {
        guard let column = sqlColumnName else { return .none }
        switch self {
        case .all:
            return .none
        case .column:
            return .columnNotEmpty(column: column)
        case .value(_, let value):
            return .equals(column: column, value: value)
        }
    }
}
