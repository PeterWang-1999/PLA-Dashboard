import Foundation

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
