import Foundation

struct PlaProductTagSnapshot: Sendable {
    let reportDay: String
    var tags: Set<String>
}

struct PlaDeliveryDetailColumnMap: Sendable {
    /// 自建站投放明细无广告系列维度时的占位值。
    static let placeholderCampaign = ""
    /// 自建站投放明细无币种列时的占位值。
    static let placeholderCurrencyCode = "USD"

    let dateIndex: Int
    let lsinIndex: Int
    let marketCostIndex: Int
    let impressionsIndex: Int
    let clicksIndex: Int
    let conversionsIndex: Int
    let conversionValueIndex: Int
    /// 可选：业务首次上架时间，用于新品判定。
    let firstListedAtIndex: Int?
    private let categoryIndices: [Int?]
    private let productTagIndex: Int?

    init(headers: [String]) throws {
        let normalizedHeaders = headers.map(ImportTextEncoding.normalizeHeaderField)

        func index(of column: String) throws -> Int {
            guard let found = normalizedHeaders.firstIndex(of: column) else {
                throw PlaDeliveryDetailColumnMapError.missingColumn(column)
            }
            return found
        }

        dateIndex = try index(of: "日期")
        lsinIndex = try index(of: "LSIN")
        marketCostIndex = try index(of: "Market Cost")
        impressionsIndex = try index(of: "Impressions")
        clicksIndex = try index(of: "Clicks")
        conversionsIndex = try index(of: "Conversions")
        conversionValueIndex = try index(of: "Conversion Value")
        firstListedAtIndex = normalizedHeaders.firstIndex(of: "首次上架时间")
        productTagIndex = normalizedHeaders.firstIndex { header in
            header.filter { !$0.isWhitespace }.lowercased() == "producttag"
        }
        categoryIndices = ["一", "二", "三", "四"].enumerated().map { index, level in
            normalizedHeaders.firstIndex(of: "CMS\(index + 1)") ??
                normalizedHeaders.firstIndex(of: "\(level)级品类")
        }
    }

    func category(in fields: [String]) -> PlaProductCategory? {
        let values = categoryIndices.map { index in index.flatMap { value(at: $0, in: fields) } }
        let levels = values.prefix { $0 != nil }.compactMap { $0 }
        let path = levels.isEmpty ? nil : levels.joined(separator: ProductCategoryPath.storageSeparator)
        guard path != nil || values[2] != nil else { return nil }
        return PlaProductCategory(path: path, cms3: values[2])
    }

    func productTags(in fields: [String]) -> Set<String>? {
        guard let productTagIndex else { return nil }
        guard let raw = value(at: productTagIndex, in: fields) else { return [] }
        return [raw]
    }

    func value(at index: Int, in fields: [String]) -> String? {
        guard index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PlaDeliveryDetailColumnMapError: Error, LocalizedError {
    case missingColumn(String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            "文件缺少必需列：\(name)"
        }
    }
}
