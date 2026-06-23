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

    /// Catalog 中的二级 / 三级片段（非 DB 完整路径）。
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

    /// `google_product_category` 完整路径的 LIKE 匹配模式（含一级前缀）。
    struct SQLMatch: Equatable {
        let exactSuffixPattern: String
        let nestedSuffixPattern: String
    }

    var sqlMatch: SQLMatch? {
        switch self {
        case .all:
            return nil
        case .level2(let level2):
            let suffix = " > \(level2)"
            return SQLMatch(
                exactSuffixPattern: "%\(suffix)",
                nestedSuffixPattern: "%\(suffix) > %"
            )
        case .level3(let level2, let level3):
            let suffix = " > \(level2) > \(level3)"
            return SQLMatch(
                exactSuffixPattern: "%\(suffix)",
                nestedSuffixPattern: "%\(suffix) > %"
            )
        }
    }
}
