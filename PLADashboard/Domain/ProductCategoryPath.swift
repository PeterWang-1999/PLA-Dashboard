import Foundation

/// Merchant Center 类目路径：三方站与自建站导出格式不同，统一解析为展示层级与存储路径。
enum ProductCategoryPath {
    /// 自建站各层级之间的分隔符（`cXXXX_` 代码后缀后的 ` > `）。
    static let selfBuiltLevelSeparator = " > "
    /// 入库与筛选共用的展示路径分隔符（与三方站 `google 商品类别` 一致）。
    static let storageSeparator = " > "
    /// 遗留原始格式检测：仍含未规范化的 `cXXXX_` 代码片段。
    private static let selfBuiltCodeSuffixPattern = #" c\d+_"#

    static func categoryColumnName(for accountKind: WorkspaceAccountKind) -> String {
        switch accountKind {
        case .thirdParty:
            "google 商品类别"
        case .selfBuilt:
            "类型"
        }
    }

    /// 去掉自建站片段末尾的类目代码（如 ` c3349_`）。
    static func displayName(fromSelfBuiltSegment segment: String) -> String {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #" c\d+_$"#, options: .regularExpression) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound])
    }

    static func parseSelfBuiltDisplayLevels(_ raw: String) -> [String] {
        raw.components(separatedBy: selfBuiltLevelSeparator)
            .map { displayName(fromSelfBuiltSegment: $0) }
            .filter { !$0.isEmpty }
    }

    static func parseThirdPartyDisplayLevels(_ raw: String) -> [String] {
        raw.split(separator: ">", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseDisplayLevels(_ raw: String, accountKind: WorkspaceAccountKind) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if accountKind == .selfBuilt || raw.range(of: selfBuiltCodeSuffixPattern, options: .regularExpression) != nil {
            return parseSelfBuiltDisplayLevels(trimmed)
        }
        return parseThirdPartyDisplayLevels(trimmed)
    }

    /// 将原始 TSV 值规范为 `一级 > 二级 > …` 展示路径；层级不足时返回 `nil`。
    static func normalizedForStorage(_ raw: String, accountKind: WorkspaceAccountKind) -> String? {
        let levels = parseDisplayLevels(raw, accountKind: accountKind)
        guard levels.count >= 2 else { return nil }
        return levels.joined(separator: storageSeparator)
    }

    /// 导入写入 `products.google_product_category` 的值：自建站规范化，三方站保留原样（浅层路径除外）。
    static func storedValue(from raw: String, accountKind: WorkspaceAccountKind) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy(\.isNumber) else { return nil }

        if let normalized = normalizedForStorage(trimmed, accountKind: accountKind) {
            return normalized
        }
        return trimmed
    }

    /// 从数据库读出的路径规范为展示路径（兼容导入前遗留的自建站原始格式）。
    static func normalizedForCatalog(fromStored stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: selfBuiltCodeSuffixPattern, options: .regularExpression) != nil else {
            return trimmed
        }
        return normalizedForStorage(trimmed, accountKind: .selfBuilt) ?? trimmed
    }
}
