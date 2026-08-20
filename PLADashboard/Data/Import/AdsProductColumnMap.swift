import Foundation

struct AdsProductColumnMap: Sendable {
    static let requiredColumns = [
        "天",
        "产品 ID",
        "广告系列",
        "货币代码",
        "费用",
        "展示次数",
        "点击次数",
        "转化次数",
        "转化价值"
    ]

    let dateIndex: Int
    let itemIdIndex: Int
    let campaignIndex: Int
    let currencyCodeIndex: Int
    let costIndex: Int
    let impressionsIndex: Int
    let clicksIndex: Int
    let conversionsIndex: Int
    let conversionValueIndex: Int

    init(headers: [String]) throws {
        let normalizedHeaders = headers.map(ImportTextEncoding.normalizeHeaderField)

        func index(of column: String) throws -> Int {
            guard let found = normalizedHeaders.firstIndex(of: column) else {
                throw AdsProductColumnMapError.missingColumn(column)
            }
            return found
        }

        dateIndex = try index(of: "天")
        itemIdIndex = try index(of: "产品 ID")
        campaignIndex = try index(of: "广告系列")
        currencyCodeIndex = try index(of: "货币代码")
        costIndex = try index(of: "费用")
        impressionsIndex = try index(of: "展示次数")
        clicksIndex = try index(of: "点击次数")
        conversionsIndex = try index(of: "转化次数")
        conversionValueIndex = try index(of: "转化价值")
    }

    static func headerMatchScore(_ headers: [String]) -> Int {
        let normalizedHeaders = Set(headers.map(ImportTextEncoding.normalizeHeaderField))
        return requiredColumns.reduce(into: 0) { score, column in
            if normalizedHeaders.contains(column) {
                score += 1
            }
        }
    }

    func value(at index: Int, in fields: [String]) -> String? {
        guard index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AdsProductColumnMapError: Error, LocalizedError {
    case missingColumn(String)
    case headerNotFound

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            "文件缺少必需列：\(name)"
        case .headerNotFound:
            "未找到 Google Ads 产品数据表头。请确认文件包含“天”“产品 ID”“广告系列”等标准列。"
        }
    }
}
