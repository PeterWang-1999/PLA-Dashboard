import Foundation

/// 从 Merchant Center TSV 的 `google 商品类别` 列解析出的二级 / 三级类目树。
struct GoogleProductCategoryCatalog: Hashable, Codable {
    struct Group: Hashable, Codable, Identifiable {
        let level2: String
        let level3: [String]

        var id: String { level2 }

        var hasLevel3Children: Bool { !level3.isEmpty }
    }

    let groups: [Group]

    static let empty = GoogleProductCategoryCatalog(groups: [])

    static func loadBundled() -> GoogleProductCategoryCatalog {
        guard let url = Bundle.main.url(forResource: "ProductCategoryCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(GoogleProductCategoryCatalog.self, from: data)
        else {
            return .previewFallback
        }
        return catalog
    }

    /// 解析用户上传的 Merchant Center TSV。`google 商品类别` 使用 `>` 分隔层级。
    static func parse(from tsvURL: URL) throws -> GoogleProductCategoryCatalog {
        let content = try String(contentsOf: tsvURL, encoding: .utf8)
        return try parse(tsvContent: content)
    }

    static func parse(tsvContent: String) throws -> GoogleProductCategoryCatalog {
        var lines = tsvContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let headerLine = lines.first else {
            return .empty
        }
        lines.removeFirst()

        let headers = parseTSVFields(String(headerLine))
        guard let columnIndex = headers.firstIndex(of: "google 商品类别") else {
            throw GoogleProductCategoryCatalogError.missingCategoryColumn
        }

        var tree: [String: Set<String>] = [:]
        for line in lines {
            let fields = parseTSVFields(String(line))
            guard columnIndex < fields.count else { continue }
            let raw = fields[columnIndex].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.allSatisfy({ $0.isNumber }), raw.contains(">") else { continue }

            let parts = raw
                .split(separator: ">", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let level2 = parts[1]
            if parts.count >= 3 {
                tree[level2, default: []].insert(parts[2])
            } else {
                _ = tree[level2, default: []]
            }
        }

        let groups = tree.keys.sorted().map { level2 in
            Group(level2: level2, level3: Array(tree[level2, default: []]).sorted())
        }
        return GoogleProductCategoryCatalog(groups: groups)
    }

    private static func parseTSVFields(_ line: String) -> [String] {
        // Merchant Center 导出以制表符分隔；当前样本未出现字段内换行。
        line.components(separatedBy: "\t")
    }

    private static let previewFallback = GoogleProductCategoryCatalog(groups: [
        Group(level2: "Clothing", level3: ["Dresses", "Pants", "Shirts & Tops", "Skirts", "Swimwear"]),
        Group(level2: "Shoes", level3: []),
    ])
}

enum GoogleProductCategoryCatalogError: Error, LocalizedError {
    case missingCategoryColumn

    var errorDescription: String? {
        switch self {
        case .missingCategoryColumn:
            "TSV 中未找到 google 商品类别 列"
        }
    }
}
