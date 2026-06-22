import Foundation

/// 类目筛选的单一选中状态：占位、仅二级、或二级+三级。
enum CategoryFilterSelection: Hashable, Codable {
    case none
    case level2(String)
    case level3(level2: String, level3: String)

    static let placeholderTitle = "二级类目 / 三级类目筛选"

    var menuTitle: String {
        switch self {
        case .none:
            Self.placeholderTitle
        case .level2(let level2):
            level2
        case .level3(_, let level3):
            level3
        }
    }

    var isActive: Bool {
        self != .none
    }

    /// 用于后续 SQL / FTS 筛选的完整路径前缀（阶段 2 接入）。
    var filterPathPrefix: String? {
        switch self {
        case .none:
            nil
        case .level2(let level2):
            level2
        case .level3(let level2, let level3):
            "\(level2) > \(level3)"
        }
    }
}
