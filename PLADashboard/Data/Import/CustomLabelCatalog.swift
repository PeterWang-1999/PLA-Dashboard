import Foundation

/// 从 Merchant Center TSV 的 `自定义标签 0`…`自定义标签 4` 列解析出的筛选项。
struct CustomLabelCatalog: Hashable, Codable {
    struct Group: Hashable, Codable, Identifiable {
        let columnName: String
        let values: [String]

        var id: String { columnName }

        var hasValueChildren: Bool { !values.isEmpty }
    }

    let groups: [Group]

    static let columnNames = (0...4).map { "自定义标签 \($0)" }

    static let empty = CustomLabelCatalog(groups: [])

    static func loadBundled() -> CustomLabelCatalog {
        guard let url = Bundle.main.url(forResource: "ProductCustomLabelCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CustomLabelCatalog.self, from: data)
        else {
            return .previewFallback
        }
        return catalog
    }

    static func parse(from tsvURL: URL) throws -> CustomLabelCatalog {
        let content = try String(contentsOf: tsvURL, encoding: .utf8)
        return try parse(tsvContent: content)
    }

    static func parse(tsvContent: String) throws -> CustomLabelCatalog {
        var lines = tsvContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let headerLine = lines.first else {
            return .empty
        }
        lines.removeFirst()

        let headers = parseTSVFields(String(headerLine))
        let columnIndexes = columnNames.compactMap { name -> (String, Int)? in
            guard let index = headers.firstIndex(of: name) else { return nil }
            return (name, index)
        }
        guard !columnIndexes.isEmpty else {
            throw CustomLabelCatalogError.missingCustomLabelColumns
        }

        var valuesByColumn: [String: Set<String>] = Dictionary(
            uniqueKeysWithValues: columnIndexes.map { ($0.0, Set<String>()) }
        )

        for line in lines {
            let fields = parseTSVFields(String(line))
            for (columnName, index) in columnIndexes {
                guard index < fields.count else { continue }
                let raw = fields[index].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                valuesByColumn[columnName, default: []].insert(raw)
            }
        }

        let groups = columnIndexes.map { columnName, _ in
            Group(
                columnName: columnName,
                values: Array(valuesByColumn[columnName, default: []]).sorted()
            )
        }
        return CustomLabelCatalog(groups: groups)
    }

    private static func parseTSVFields(_ line: String) -> [String] {
        line.components(separatedBy: "\t")
    }

    private static let previewFallback = CustomLabelCatalog(groups: [
        Group(columnName: "自定义标签 0", values: ["EN", "Shopify产品", "shopify产品"]),
        Group(columnName: "自定义标签 1", values: ["elite-企划部"]),
    ])
}

enum CustomLabelCatalogError: Error, LocalizedError {
    case missingCustomLabelColumns

    var errorDescription: String? {
        switch self {
        case .missingCustomLabelColumns:
            "TSV 中未找到自定义标签列"
        }
    }
}
