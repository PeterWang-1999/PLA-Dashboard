import Foundation

/// 类目筛选：默认「全部类目」，或选中二级 / 三级。
enum CategoryFilterSelection: Hashable, Codable {
    case all
    case level2(String)
    case level3(level2: String, level3: String)

    static let defaultTitle = "全部类目"

    var menuTitle: String {
        switch self {
        case .all:
            Self.defaultTitle
        case .level2(let level2):
            level2
        case .level3(_, let level3):
            level3
        }
    }

    /// 是否已应用具体类目筛选（非默认「全部类目」）。
    var isFiltered: Bool {
        self != .all
    }

    /// 用于后续 SQL / FTS 筛选的完整路径前缀（阶段 2 接入）。
    var filterPathPrefix: String? {
        switch self {
        case .all:
            nil
        case .level2(let level2):
            level2
        case .level3(let level2, let level3):
            "\(level2) > \(level3)"
        }
    }
}
