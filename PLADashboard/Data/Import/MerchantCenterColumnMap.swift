import Foundation

/// Google Merchant Center TSV 导出格式因账户类型而异（列名方言）。
struct MerchantCenterExportFormat: Sendable {
    let accountKind: WorkspaceAccountKind

    static func forAccountKind(_ accountKind: WorkspaceAccountKind) -> MerchantCenterExportFormat {
        MerchantCenterExportFormat(accountKind: accountKind)
    }

    var canonicalLinkColumnName: String {
        switch accountKind {
        case .thirdParty:
            "canonical link"
        case .selfBuilt:
            "链接"
        }
    }

    var requiredColumnNames: [String] {
        [
            "序号",
            "标题",
            canonicalLinkColumnName,
            "图片链接",
        ]
    }

    static let customLabelColumnNames = (0...4).map { "自定义标签 \($0)" }
    static let categoryColumnName = "google 商品类别"

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

        func index(of column: String) throws -> Int {
            guard let found = headers.firstIndex(of: column) else {
                throw MerchantCenterColumnMapError.missingColumn(column, accountKind: accountKind)
            }
            return found
        }

        itemIdIndex = try index(of: "序号")
        titleIndex = try index(of: "标题")
        canonicalLinkIndex = try index(of: format.canonicalLinkColumnName)
        imageURLIndex = try index(of: "图片链接")

        var labels: [Int: Int] = [:]
        for position in 0...4 {
            let name = MerchantCenterExportFormat.customLabelColumnNames[position]
            if let headerIndex = headers.firstIndex(of: name) {
                labels[position] = headerIndex
            }
        }
        customLabelIndexByPosition = labels
        categoryIndex = headers.firstIndex(of: MerchantCenterExportFormat.categoryColumnName)
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
    case missingColumn(String, accountKind: WorkspaceAccountKind)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name, let accountKind):
            "TSV 缺少必需列：\(name)（\(accountKind.displayName) 导出格式）"
        }
    }
}
