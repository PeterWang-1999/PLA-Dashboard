import Foundation

/// Google Merchant Center TSV 导出格式因账户类型而异（列名方言；中英文表头均支持）。
struct MerchantCenterExportFormat: Sendable {
    let accountKind: WorkspaceAccountKind

    static func forAccountKind(_ accountKind: WorkspaceAccountKind) -> MerchantCenterExportFormat {
        MerchantCenterExportFormat(accountKind: accountKind)
    }

    /// 产品 ID：`序号` / `id`
    static let itemIdColumnAliases = ["序号", "id"]

    /// 标题：`标题` / `title`
    static let titleColumnAliases = ["标题", "title"]

    /// 图片链接：`图片链接` / `image link`
    static let imageURLColumnAliases = ["图片链接", "image link"]

    /// 商品链接：三方站 `canonical link`；自建站 `链接` / `link`。
    var canonicalLinkColumnAliases: [String] {
        switch accountKind {
        case .thirdParty:
            ["canonical link", "link"]
        case .selfBuilt:
            ["链接", "link"]
        }
    }

    /// 展示用主列名（错误提示等）。
    var canonicalLinkColumnName: String {
        canonicalLinkColumnAliases[0]
    }

    var requiredColumnAliases: [[String]] {
        [
            Self.itemIdColumnAliases,
            Self.titleColumnAliases,
            canonicalLinkColumnAliases,
            Self.imageURLColumnAliases,
        ]
    }

    var requiredColumnNames: [String] {
        requiredColumnAliases.compactMap(\.first)
    }

    static let customLabelColumnNames = (0...4).map { "自定义标签 \($0)" }

    static func customLabelColumnAliases(position: Int) -> [String] {
        ["自定义标签 \(position)", "custom label \(position)"]
    }

    var categoryColumnName: String {
        ProductCategoryPath.categoryColumnName(for: accountKind)
    }

    static func sampleResourceName(for accountKind: WorkspaceAccountKind) -> String {
        switch accountKind {
        case .thirdParty:
            "SampleMerchant"
        case .selfBuilt:
            "SampleMerchantSelfBuilt"
        }
    }
}

struct MerchantCenterColumnMap: Sendable {
    let itemIdIndex: Int
    let titleIndex: Int
    let canonicalLinkIndex: Int
    let imageURLIndex: Int
    let customLabelIndexByPosition: [Int: Int]
    let categoryIndex: Int?

    init(headers: [String], accountKind: WorkspaceAccountKind) throws {
        let format = MerchantCenterExportFormat.forAccountKind(accountKind)

        func index(ofAliases aliases: [String]) throws -> Int {
            guard let found = Self.firstIndex(in: headers, matchingAnyOf: aliases) else {
                throw MerchantCenterColumnMapError.missingColumn(aliases, accountKind: accountKind)
            }
            return found
        }

        itemIdIndex = try index(ofAliases: MerchantCenterExportFormat.itemIdColumnAliases)
        titleIndex = try index(ofAliases: MerchantCenterExportFormat.titleColumnAliases)
        canonicalLinkIndex = try index(ofAliases: format.canonicalLinkColumnAliases)
        imageURLIndex = try index(ofAliases: MerchantCenterExportFormat.imageURLColumnAliases)

        var labels: [Int: Int] = [:]
        for position in 0...4 {
            let aliases = MerchantCenterExportFormat.customLabelColumnAliases(position: position)
            if let headerIndex = Self.firstIndex(in: headers, matchingAnyOf: aliases) {
                labels[position] = headerIndex
            }
        }
        customLabelIndexByPosition = labels
        categoryIndex = headers.firstIndex(of: format.categoryColumnName)
    }

    private static func firstIndex(in headers: [String], matchingAnyOf aliases: [String]) -> Int? {
        for alias in aliases {
            if let index = headers.firstIndex(of: alias) {
                return index
            }
        }
        return nil
    }

    func value(at index: Int?, in fields: [String]) -> String? {
        guard let index, index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func customLabel(at position: Int, in fields: [String]) -> String? {
        guard let index = customLabelIndexByPosition[position] else { return nil }
        return value(at: index, in: fields)
    }
}

enum MerchantCenterColumnMapError: Error, LocalizedError {
    case missingColumn([String], accountKind: WorkspaceAccountKind)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let aliases, let accountKind):
            "TSV 缺少必需列：\(aliases.joined(separator: " / "))（\(accountKind.displayName) 导出格式）"
        }
    }
}
