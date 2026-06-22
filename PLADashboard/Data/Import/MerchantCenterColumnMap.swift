import Foundation

struct MerchantCenterColumnMap: Sendable {
    let itemIdIndex: Int
    let titleIndex: Int
    let canonicalLinkIndex: Int
    let imageURLIndex: Int
    let customLabelIndexByPosition: [Int: Int]
    let categoryIndex: Int?

    static let requiredColumns = [
        "序号",
        "标题",
        "canonical link",
        "图片链接",
    ]

    static let customLabelColumnNames = (0...4).map { "自定义标签 \($0)" }
    static let categoryColumnName = "google 商品类别"

    init(headers: [String]) throws {
        func index(of column: String) throws -> Int {
            guard let found = headers.firstIndex(of: column) else {
                throw MerchantCenterColumnMapError.missingColumn(column)
            }
            return found
        }

        itemIdIndex = try index(of: "序号")
        titleIndex = try index(of: "标题")
        canonicalLinkIndex = try index(of: "canonical link")
        imageURLIndex = try index(of: "图片链接")

        var labels: [Int: Int] = [:]
        for position in 0...4 {
            let name = Self.customLabelColumnNames[position]
            if let headerIndex = headers.firstIndex(of: name) {
                labels[position] = headerIndex
            }
        }
        customLabelIndexByPosition = labels
        categoryIndex = headers.firstIndex(of: Self.categoryColumnName)
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
    case missingColumn(String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            "TSV 缺少必需列：\(name)"
        }
    }
}
